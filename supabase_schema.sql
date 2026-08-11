-- Supabase Schema for Cloud Kitchen MVP
-- Execute this script in the Supabase SQL Editor.

-- Drop existing objects if they exist
-- 1. Drop trigger on auth.users (auth schema always exists)
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

-- 2. Drop all tables (this automatically drops triggers associated with them)
DROP TABLE IF EXISTS public.ratings CASCADE;
DROP TABLE IF EXISTS public.messages CASCADE;
DROP TABLE IF EXISTS public.chats CASCADE;
DROP TABLE IF EXISTS public.order_items CASCADE;
DROP TABLE IF EXISTS public.orders CASCADE;
DROP TABLE IF EXISTS public.menu_items CASCADE;
DROP TABLE IF EXISTS public.kitchens CASCADE;
DROP TABLE IF EXISTS public.profiles CASCADE;

-- 3. Drop functions
DROP FUNCTION IF EXISTS public.handle_new_user() CASCADE;
DROP FUNCTION IF EXISTS public.check_profile_update() CASCADE;
DROP FUNCTION IF EXISTS public.handle_order_status_change() CASCADE;
DROP FUNCTION IF EXISTS public.check_order_assignment() CASCADE;
DROP FUNCTION IF EXISTS public.handle_update_timestamp() CASCADE;
DROP FUNCTION IF EXISTS public.top_up_wallet(numeric) CASCADE;

-- 4. Drop types (no longer needed, using robust TEXT + CHECK constraints)
DROP TYPE IF EXISTS user_role CASCADE;
DROP TYPE IF EXISTS order_status CASCADE;
DROP TYPE IF EXISTS rating_type CASCADE;

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- 1. Profiles Table
CREATE TABLE public.profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email TEXT NOT NULL,
  full_name TEXT,
  role TEXT NOT NULL DEFAULT 'customer' CHECK (role IN ('customer', 'kitchen_owner', 'rider')),
  phone TEXT,
  -- Personal bKash "Send Money" number, set/edited by the user themselves.
  -- Private until contextually revealed (customer sees the kitchen's number
  -- once they've placed an order; kitchen owner sees the rider's number once
  -- the rider has picked up the order).
  bkash_number TEXT,
  avatar_url TEXT,
  latitude NUMERIC(9, 6),
  longitude NUMERIC(9, 6),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- 2. Kitchens Table
CREATE TABLE public.kitchens (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  description TEXT,
  address TEXT,
  image_url TEXT,
  latitude NUMERIC(9, 6) NOT NULL,
  longitude NUMERIC(9, 6) NOT NULL,
  is_active BOOLEAN DEFAULT true NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
  UNIQUE(owner_id)
);

-- 3. Menu Items Table
CREATE TABLE public.menu_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  kitchen_id UUID NOT NULL REFERENCES public.kitchens(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  description TEXT,
  price NUMERIC(10, 2) NOT NULL CHECK (price >= 0),
  -- image_url mirrors image_urls[0] for any code path still reading a single
  -- photo directly; image_urls is the source of truth (multiple photos per item).
  image_url TEXT,
  image_urls TEXT[] NOT NULL DEFAULT '{}',
  is_available BOOLEAN DEFAULT true NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- 4. Orders Table
CREATE TABLE public.orders (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id UUID NOT NULL REFERENCES public.profiles(id),
  kitchen_id UUID NOT NULL REFERENCES public.kitchens(id),
  rider_id UUID REFERENCES public.profiles(id),
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN (
    'pending', 'accepted', 'rejected', 'preparing', 'ready', 'awaiting_rider',
    'rider_assigned', 'picked_up', 'on_the_way', 'arrived', 'delivered', 'completed'
  )),
  total_amount NUMERIC(10, 2) NOT NULL CHECK (total_amount >= 0),
  commission_amount NUMERIC(10, 2) NOT NULL DEFAULT 0.00 CHECK (commission_amount >= 0),
  rider_fee NUMERIC(10, 2) NOT NULL DEFAULT 0.00 CHECK (rider_fee >= 0),
  delivery_address TEXT NOT NULL,
  delivery_latitude NUMERIC(9, 6) NOT NULL,
  delivery_longitude NUMERIC(9, 6) NOT NULL,
  confirmed_by_customer BOOLEAN NOT NULL DEFAULT false,
  -- Manual bKash payment lifecycle: customer sends money via bKash "Send
  -- Money" and reports the transaction ID; kitchen owner verifies in their
  -- own bKash app/SMS and confirms receipt before accepting the order.
  payment_status TEXT NOT NULL DEFAULT 'awaiting_payment'
    CHECK (payment_status IN ('awaiting_payment', 'payment_reported', 'payment_confirmed')),
  customer_bkash_txn_id TEXT,
  payment_reported_at TIMESTAMP WITH TIME ZONE,
  payment_confirmed_at TIMESTAMP WITH TIME ZONE,
  -- Rider payout: kitchen owner sends the rider's fee via bKash once the
  -- order is delivered and marks it paid here (optionally with a
  -- transaction ID for their own records), then the rider confirms they
  -- actually received it — that final confirmation, not the kitchen
  -- owner's claim, is what unblocks the customer's delivery confirmation.
  rider_payout_confirmed BOOLEAN NOT NULL DEFAULT false,
  rider_payout_txn_id TEXT,
  rider_paid_at TIMESTAMP WITH TIME ZONE,
  rider_payment_confirmed BOOLEAN NOT NULL DEFAULT false,
  rider_payment_confirmed_at TIMESTAMP WITH TIME ZONE,
  -- Set once the kitchen owner issues the in-app payment receipt.
  receipt_issued_at TIMESTAMP WITH TIME ZONE,
  -- Set when the customer's delivery confirmation goes through via the 24h
  -- payout timeout safety valve instead of a confirmed rider payout — flags
  -- the kitchen owner's account for payout follow-up/collection.
  payout_overdue_flagged_at TIMESTAMP WITH TIME ZONE,
  accepted_at TIMESTAMP WITH TIME ZONE,
  ready_at TIMESTAMP WITH TIME ZONE,
  picked_up_at TIMESTAMP WITH TIME ZONE,
  delivered_at TIMESTAMP WITH TIME ZONE,
  confirmed_at TIMESTAMP WITH TIME ZONE,
  completed_at TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- 5. Order Items Table
CREATE TABLE public.order_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  menu_item_id UUID NOT NULL REFERENCES public.menu_items(id),
  quantity INTEGER NOT NULL CHECK (quantity > 0),
  price NUMERIC(10, 2) NOT NULL CHECK (price >= 0)
);

-- 6. Chats Table
CREATE TABLE public.chats (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
  UNIQUE(order_id)
);

-- 7. Messages Table
-- message_text defaults to '' to allow image-only messages (see image_url
-- below and the messages_text_or_image_chk constraint further down).
CREATE TABLE public.messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  chat_id UUID NOT NULL REFERENCES public.chats(id) ON DELETE CASCADE,
  sender_id UUID NOT NULL REFERENCES public.profiles(id),
  message_text TEXT NOT NULL DEFAULT '',
  image_url TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
  CONSTRAINT messages_text_or_image_chk CHECK (length(trim(message_text)) > 0 OR image_url IS NOT NULL)
);

-- 8. Ratings Table
CREATE TABLE public.ratings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  rater_id UUID NOT NULL REFERENCES public.profiles(id),
  ratee_id UUID NOT NULL REFERENCES public.profiles(id),
  rating_type TEXT NOT NULL CHECK (rating_type IN ('kitchen', 'rider')),
  score INTEGER NOT NULL CHECK (score >= 1 AND score <= 5),
  review TEXT,
  -- Photos attached to the review (multiple allowed), uploaded to the
  -- `review-photos` bucket under the rater's own folder.
  photo_urls TEXT[] NOT NULL DEFAULT '{}',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
  UNIQUE(order_id, rating_type)
);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_profiles_role ON public.profiles(role);
CREATE INDEX IF NOT EXISTS idx_kitchens_owner ON public.kitchens(owner_id);
CREATE INDEX IF NOT EXISTS idx_menu_items_kitchen ON public.menu_items(kitchen_id);
CREATE INDEX IF NOT EXISTS idx_orders_customer ON public.orders(customer_id);
CREATE INDEX IF NOT EXISTS idx_orders_kitchen ON public.orders(kitchen_id);
CREATE INDEX IF NOT EXISTS idx_orders_rider ON public.orders(rider_id);
CREATE INDEX IF NOT EXISTS idx_orders_status ON public.orders(status);
CREATE INDEX IF NOT EXISTS idx_messages_chat ON public.messages(chat_id);
CREATE INDEX IF NOT EXISTS idx_ratings_order ON public.ratings(order_id);

-- ENABLE ROW LEVEL SECURITY
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.kitchens ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.menu_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chats ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ratings ENABLE ROW LEVEL SECURITY;

-- GRANT table-level permissions to authenticated and anon roles
-- (RLS policies control row-level access, but table-level GRANT is required first)
GRANT USAGE ON SCHEMA public TO anon, authenticated;

GRANT SELECT ON public.profiles TO authenticated;
GRANT INSERT ON public.profiles TO authenticated;
GRANT UPDATE ON public.profiles TO authenticated;

GRANT SELECT ON public.kitchens TO authenticated;
GRANT INSERT ON public.kitchens TO authenticated;
GRANT UPDATE ON public.kitchens TO authenticated;

GRANT SELECT ON public.menu_items TO authenticated;
GRANT INSERT ON public.menu_items TO authenticated;
GRANT UPDATE ON public.menu_items TO authenticated;
GRANT DELETE ON public.menu_items TO authenticated;

GRANT SELECT ON public.orders TO authenticated;
GRANT INSERT ON public.orders TO authenticated;
GRANT UPDATE ON public.orders TO authenticated;

GRANT SELECT ON public.order_items TO authenticated;
GRANT INSERT ON public.order_items TO authenticated;

GRANT SELECT ON public.chats TO authenticated;
GRANT INSERT ON public.chats TO authenticated;

GRANT SELECT ON public.messages TO authenticated;
GRANT INSERT ON public.messages TO authenticated;

GRANT SELECT ON public.ratings TO authenticated;
GRANT INSERT ON public.ratings TO authenticated;

-- Grant execute on RPC functions
GRANT EXECUTE ON FUNCTION public.create_order(uuid, uuid, integer, text, numeric, numeric) TO authenticated;

-- 1. Profiles Policies
CREATE POLICY "Profiles are viewable by authenticated users" 
  ON public.profiles FOR SELECT TO authenticated USING (true);

CREATE POLICY "Users can insert their own profile" 
  ON public.profiles FOR INSERT TO authenticated 
  WITH CHECK (auth.uid() = id);

CREATE POLICY "Users can update their own profile" 
  ON public.profiles FOR UPDATE TO authenticated 
  USING (auth.uid() = id) 
  WITH CHECK (auth.uid() = id);

-- 2. Kitchens Policies
CREATE POLICY "Kitchens are viewable by all authenticated users" 
  ON public.kitchens FOR SELECT TO authenticated USING (true);

CREATE POLICY "Kitchen owners can insert their kitchen" 
  ON public.kitchens FOR INSERT TO authenticated 
  WITH CHECK (auth.uid() = owner_id);

CREATE POLICY "Kitchen owners can update their kitchen" 
  ON public.kitchens FOR UPDATE TO authenticated 
  USING (auth.uid() = owner_id) 
  WITH CHECK (auth.uid() = owner_id);

-- 3. Menu Items Policies
CREATE POLICY "Menu items are viewable by all authenticated users" 
  ON public.menu_items FOR SELECT TO authenticated USING (true);

CREATE POLICY "Kitchen owners can insert menu items" 
  ON public.menu_items FOR INSERT TO authenticated 
  WITH CHECK (EXISTS (SELECT 1 FROM public.kitchens WHERE id = kitchen_id AND owner_id = auth.uid()));

CREATE POLICY "Kitchen owners can update menu items" 
  ON public.menu_items FOR UPDATE TO authenticated 
  USING (EXISTS (SELECT 1 FROM public.kitchens WHERE id = kitchen_id AND owner_id = auth.uid())) 
  WITH CHECK (EXISTS (SELECT 1 FROM public.kitchens WHERE id = kitchen_id AND owner_id = auth.uid()));

CREATE POLICY "Kitchen owners can delete menu items" 
  ON public.menu_items FOR DELETE TO authenticated 
  USING (EXISTS (SELECT 1 FROM public.kitchens WHERE id = kitchen_id AND owner_id = auth.uid()));

-- 4. Orders Policies
CREATE POLICY "Users can view their own orders"
  ON public.orders FOR SELECT TO authenticated
  USING (
    customer_id = auth.uid() OR
    rider_id = auth.uid() OR
    -- Any rider needs to see unclaimed deliveries to be able to accept one
    (status = 'awaiting_rider' AND rider_id IS NULL) OR
    EXISTS (SELECT 1 FROM public.kitchens WHERE id = kitchen_id AND owner_id = auth.uid())
  );

CREATE POLICY "Customers can insert orders" 
  ON public.orders FOR INSERT TO authenticated 
  WITH CHECK (customer_id = auth.uid());

CREATE POLICY "Authorized users can update order status"
  ON public.orders FOR UPDATE TO authenticated
  USING (
    customer_id = auth.uid() OR
    rider_id = auth.uid() OR
    -- Allow any rider to claim an unassigned order that is awaiting a rider
    (status = 'awaiting_rider' AND rider_id IS NULL) OR
    EXISTS (SELECT 1 FROM public.kitchens WHERE id = kitchen_id AND owner_id = auth.uid())
  )
  WITH CHECK (
    customer_id = auth.uid() OR
    rider_id = auth.uid() OR
    EXISTS (SELECT 1 FROM public.kitchens WHERE id = kitchen_id AND owner_id = auth.uid())
  );

-- 5. Order Items Policies
CREATE POLICY "Order items are viewable by associated users" 
  ON public.order_items FOR SELECT TO authenticated 
  USING (
    EXISTS (
      SELECT 1 FROM public.orders 
      WHERE id = order_id AND (
        customer_id = auth.uid() OR 
        rider_id = auth.uid() OR 
        EXISTS (SELECT 1 FROM public.kitchens WHERE id = kitchen_id AND owner_id = auth.uid())
      )
    )
  );

CREATE POLICY "Customers can insert order items" 
  ON public.order_items FOR INSERT TO authenticated 
  WITH CHECK (
    EXISTS (SELECT 1 FROM public.orders WHERE id = order_id AND customer_id = auth.uid())
  );

-- 6. Chats Policies
CREATE POLICY "Chats are viewable by order participants" 
  ON public.chats FOR SELECT TO authenticated 
  USING (
    EXISTS (
      SELECT 1 FROM public.orders 
      WHERE id = order_id AND (
        customer_id = auth.uid() OR 
        rider_id = auth.uid() OR 
        EXISTS (SELECT 1 FROM public.kitchens WHERE id = kitchen_id AND owner_id = auth.uid())
      )
    )
  );

CREATE POLICY "Chats can be inserted by order participants" 
  ON public.chats FOR INSERT TO authenticated 
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.orders 
      WHERE id = order_id AND (
        customer_id = auth.uid() OR 
        rider_id = auth.uid() OR 
        EXISTS (SELECT 1 FROM public.kitchens WHERE id = kitchen_id AND owner_id = auth.uid())
      )
    )
  );

-- 7. Messages Policies
CREATE POLICY "Messages are viewable by chat participants" 
  ON public.messages FOR SELECT TO authenticated USING (
    EXISTS (
      SELECT 1 FROM public.chats c 
      JOIN public.orders o ON c.order_id = o.id 
      WHERE c.id = chat_id AND (
        o.customer_id = auth.uid() OR 
        o.rider_id = auth.uid() OR 
        EXISTS (SELECT 1 FROM public.kitchens k WHERE k.id = o.kitchen_id AND k.owner_id = auth.uid())
      )
    )
  );

CREATE POLICY "Messages can be sent by chat participants" 
  ON public.messages FOR INSERT TO authenticated 
  WITH CHECK (
    sender_id = auth.uid() AND 
    EXISTS (
      SELECT 1 FROM public.chats c 
      JOIN public.orders o ON c.order_id = o.id 
      WHERE c.id = chat_id AND (
        o.customer_id = auth.uid() OR 
        o.rider_id = auth.uid() OR 
        EXISTS (SELECT 1 FROM public.kitchens k WHERE k.id = o.kitchen_id AND k.owner_id = auth.uid())
      )
    )
  );

-- 8. Ratings Policies
CREATE POLICY "Ratings are viewable by all authenticated users" 
  ON public.ratings FOR SELECT TO authenticated USING (true);

CREATE POLICY "Customers can insert ratings" 
  ON public.ratings FOR INSERT TO authenticated 
  WITH CHECK (
    rater_id = auth.uid() AND 
    EXISTS (SELECT 1 FROM public.orders WHERE id = order_id AND customer_id = auth.uid())
  );


-- STORAGE BUCKETS & POLICIES
-- Creates the two public buckets the app expects and grants public read + owner-scoped write.
-- Fixes "image uploads succeed but never display": uploadBinary()/getPublicUrl() both succeed
-- even if the bucket doesn't exist or isn't public, silently producing an unreachable URL.
INSERT INTO storage.buckets (id, name, public)
VALUES ('menu-images', 'menu-images', true)
ON CONFLICT (id) DO UPDATE SET public = true;

INSERT INTO storage.buckets (id, name, public)
VALUES ('avatars', 'avatars', true)
ON CONFLICT (id) DO UPDATE SET public = true;

DROP POLICY IF EXISTS "Public read access for menu-images" ON storage.objects;
CREATE POLICY "Public read access for menu-images"
  ON storage.objects FOR SELECT TO public
  USING (bucket_id = 'menu-images');

DROP POLICY IF EXISTS "Kitchen owners can upload menu images" ON storage.objects;
CREATE POLICY "Kitchen owners can upload menu images"
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'menu-images' AND
    EXISTS (SELECT 1 FROM public.kitchens WHERE id::text = (storage.foldername(name))[1] AND owner_id = auth.uid())
  );

DROP POLICY IF EXISTS "Kitchen owners can update their menu images" ON storage.objects;
CREATE POLICY "Kitchen owners can update their menu images"
  ON storage.objects FOR UPDATE TO authenticated
  USING (
    bucket_id = 'menu-images' AND
    EXISTS (SELECT 1 FROM public.kitchens WHERE id::text = (storage.foldername(name))[1] AND owner_id = auth.uid())
  );

DROP POLICY IF EXISTS "Kitchen owners can delete their menu images" ON storage.objects;
CREATE POLICY "Kitchen owners can delete their menu images"
  ON storage.objects FOR DELETE TO authenticated
  USING (
    bucket_id = 'menu-images' AND
    EXISTS (SELECT 1 FROM public.kitchens WHERE id::text = (storage.foldername(name))[1] AND owner_id = auth.uid())
  );

DROP POLICY IF EXISTS "Public read access for avatars" ON storage.objects;
CREATE POLICY "Public read access for avatars"
  ON storage.objects FOR SELECT TO public
  USING (bucket_id = 'avatars');

DROP POLICY IF EXISTS "Users can upload their own avatar" ON storage.objects;
CREATE POLICY "Users can upload their own avatar"
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'avatars' AND (storage.foldername(name))[1] = auth.uid()::text);

DROP POLICY IF EXISTS "Users can update their own avatar" ON storage.objects;
CREATE POLICY "Users can update their own avatar"
  ON storage.objects FOR UPDATE TO authenticated
  USING (bucket_id = 'avatars' AND (storage.foldername(name))[1] = auth.uid()::text);

DROP POLICY IF EXISTS "Users can delete their own avatar" ON storage.objects;
CREATE POLICY "Users can delete their own avatar"
  ON storage.objects FOR DELETE TO authenticated
  USING (bucket_id = 'avatars' AND (storage.foldername(name))[1] = auth.uid()::text);

-- Review photos — multiple photos per review, uploaded by the rater
-- (customer, kitchen owner, or rider) under their own folder.
INSERT INTO storage.buckets (id, name, public)
VALUES ('review-photos', 'review-photos', true)
ON CONFLICT (id) DO UPDATE SET public = true;

DROP POLICY IF EXISTS "Public read access for review-photos" ON storage.objects;
CREATE POLICY "Public read access for review-photos"
  ON storage.objects FOR SELECT TO public
  USING (bucket_id = 'review-photos');

DROP POLICY IF EXISTS "Users can upload their own review photos" ON storage.objects;
CREATE POLICY "Users can upload their own review photos"
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'review-photos' AND (storage.foldername(name))[1] = auth.uid()::text);

DROP POLICY IF EXISTS "Users can delete their own review photos" ON storage.objects;
CREATE POLICY "Users can delete their own review photos"
  ON storage.objects FOR DELETE TO authenticated
  USING (bucket_id = 'review-photos' AND (storage.foldername(name))[1] = auth.uid()::text);

-- Chat photos — shared by either party in an order's chat, under
-- `{chatId}/{senderId}/`; readable by anyone (public bucket, mirrors the
-- other photo buckets), uploadable only by an actual participant in that
-- order's chat (customer, kitchen owner, or rider), deletable only by the
-- uploader themselves.
INSERT INTO storage.buckets (id, name, public)
VALUES ('chat-photos', 'chat-photos', true)
ON CONFLICT (id) DO UPDATE SET public = true;

DROP POLICY IF EXISTS "Public read access for chat-photos" ON storage.objects;
CREATE POLICY "Public read access for chat-photos"
  ON storage.objects FOR SELECT TO public
  USING (bucket_id = 'chat-photos');

DROP POLICY IF EXISTS "Chat participants can upload chat photos" ON storage.objects;
CREATE POLICY "Chat participants can upload chat photos"
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'chat-photos' AND
    EXISTS (
      SELECT 1 FROM public.chats c
      JOIN public.orders o ON o.id = c.order_id
      WHERE c.id::text = (storage.foldername(name))[1]
        AND (o.customer_id = auth.uid() OR o.rider_id = auth.uid() OR EXISTS (
          SELECT 1 FROM public.kitchens k WHERE k.id = o.kitchen_id AND k.owner_id = auth.uid()
        ))
    )
  );

DROP POLICY IF EXISTS "Uploaders can delete their own chat photos" ON storage.objects;
CREATE POLICY "Uploaders can delete their own chat photos"
  ON storage.objects FOR DELETE TO authenticated
  USING (bucket_id = 'chat-photos' AND (storage.foldername(name))[2] = auth.uid()::text);


-- TRIGGERS & PROCEDURES

-- A. Auto-create profiles row on signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.profiles (id, email, full_name, role)
  VALUES (
    new.id,
    new.email,
    COALESCE(new.raw_user_meta_data->>'full_name', 'User'),
    COALESCE(new.raw_user_meta_data->>'role', 'customer')
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- B. Auto-update updated_at timestamps
CREATE OR REPLACE FUNCTION public.handle_update_timestamp()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = timezone('utc'::text, now());
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_profiles_updated_at BEFORE UPDATE ON public.profiles FOR EACH ROW EXECUTE FUNCTION public.handle_update_timestamp();
CREATE TRIGGER update_kitchens_updated_at BEFORE UPDATE ON public.kitchens FOR EACH ROW EXECUTE FUNCTION public.handle_update_timestamp();
CREATE TRIGGER update_menu_items_updated_at BEFORE UPDATE ON public.menu_items FOR EACH ROW EXECUTE FUNCTION public.handle_update_timestamp();
CREATE TRIGGER update_orders_updated_at BEFORE UPDATE ON public.orders FOR EACH ROW EXECUTE FUNCTION public.handle_update_timestamp();

-- C. Enforce single-rider assignment AND valid order status transitions
CREATE OR REPLACE FUNCTION public.check_order_assignment()
RETURNS TRIGGER AS $$
BEGIN
  -- Prevent double-acceptance of a delivery by a second rider
  IF NEW.rider_id IS DISTINCT FROM OLD.rider_id THEN
    IF OLD.rider_id IS NOT NULL THEN
      RAISE EXCEPTION 'Order has already been assigned to another rider';
    END IF;
    IF NEW.rider_id IS NULL THEN
      RAISE EXCEPTION 'rider_id must be provided to assign order';
    END IF;
  END IF;

  -- Completed/rejected orders are terminal: nothing may modify status further
  IF OLD.status IN ('completed', 'rejected') AND NEW.status IS DISTINCT FROM OLD.status THEN
    RAISE EXCEPTION 'Order % is already finalized (%) and cannot be modified', OLD.id, OLD.status;
  END IF;

  -- Enforce the exact forward lifecycle (skip when status is unchanged, e.g. rider_id/location edits)
  IF NEW.status IS DISTINCT FROM OLD.status THEN
    IF NOT (
      (OLD.status = 'pending' AND NEW.status = 'rejected') OR
      (OLD.status = 'pending' AND NEW.status = 'accepted') OR
      (OLD.status = 'accepted' AND NEW.status = 'preparing') OR
      (OLD.status = 'preparing' AND NEW.status = 'ready') OR
      (OLD.status = 'ready' AND NEW.status = 'awaiting_rider') OR
      (OLD.status = 'awaiting_rider' AND NEW.status = 'rider_assigned') OR
      (OLD.status = 'rider_assigned' AND NEW.status = 'picked_up') OR
      (OLD.status = 'picked_up' AND NEW.status = 'on_the_way') OR
      (OLD.status = 'on_the_way' AND NEW.status = 'arrived') OR
      (OLD.status = 'arrived' AND NEW.status = 'delivered') OR
      (OLD.status = 'delivered' AND NEW.status = 'completed')
    ) THEN
      RAISE EXCEPTION 'Invalid order status transition: % -> %', OLD.status, NEW.status;
    END IF;

    -- Kitchen cannot accept before the customer's bKash payment is confirmed
    IF OLD.status = 'pending' AND NEW.status = 'accepted' AND NEW.payment_status <> 'payment_confirmed' THEN
      RAISE EXCEPTION 'Cannot accept order before payment is confirmed';
    END IF;

    -- Customer can only confirm (delivered -> completed); rider/kitchen cannot skip
    -- confirmation, AND the rider must have confirmed receiving their payout first —
    -- the kitchen owner marking it paid alone isn't enough — unless the 24h payout
    -- timeout has elapsed, in which case confirmation proceeds anyway and the order
    -- is flagged on the kitchen owner's account for payout follow-up.
    IF OLD.status = 'delivered' AND NEW.status = 'completed' THEN
      IF NEW.confirmed_by_customer IS NOT TRUE THEN
        RAISE EXCEPTION 'Order cannot be completed without customer confirmation';
      END IF;
      IF NOT COALESCE(NEW.rider_payment_confirmed, OLD.rider_payment_confirmed) THEN
        IF OLD.delivered_at IS NOT NULL AND (timezone('utc'::text, now()) - OLD.delivered_at) > INTERVAL '24 hours' THEN
          NEW.payout_overdue_flagged_at := timezone('utc'::text, now());
        ELSE
          RAISE EXCEPTION 'Cannot complete order until the rider confirms receiving payment from the kitchen owner (or the payout timeout has elapsed)';
        END IF;
      END IF;
    END IF;

    -- Stamp lifecycle timestamps automatically
    IF NEW.status = 'accepted' THEN NEW.accepted_at := timezone('utc'::text, now()); END IF;
    IF NEW.status = 'ready' THEN NEW.ready_at := timezone('utc'::text, now()); END IF;
    IF NEW.status = 'picked_up' THEN NEW.picked_up_at := timezone('utc'::text, now()); END IF;
    IF NEW.status = 'delivered' THEN NEW.delivered_at := timezone('utc'::text, now()); END IF;
    IF NEW.status = 'completed' THEN
      NEW.confirmed_at := timezone('utc'::text, now());
      NEW.completed_at := timezone('utc'::text, now());
    END IF;
  END IF;

  -- Payment lifecycle: customer reports sending money, kitchen owner confirms receipt
  IF NEW.payment_status IS DISTINCT FROM OLD.payment_status THEN
    IF OLD.payment_status = 'awaiting_payment' AND NEW.payment_status = 'payment_reported' THEN
      IF auth.uid() <> NEW.customer_id THEN
        RAISE EXCEPTION 'Only the customer can report having sent payment';
      END IF;
      IF NEW.customer_bkash_txn_id IS NULL OR length(trim(NEW.customer_bkash_txn_id)) = 0 THEN
        RAISE EXCEPTION 'A bKash transaction ID is required to report payment';
      END IF;
      NEW.payment_reported_at := timezone('utc'::text, now());
    ELSIF OLD.payment_status = 'payment_reported' AND NEW.payment_status = 'payment_confirmed' THEN
      IF NOT EXISTS (SELECT 1 FROM public.kitchens WHERE id = NEW.kitchen_id AND owner_id = auth.uid()) THEN
        RAISE EXCEPTION 'Only the kitchen owner can confirm payment received';
      END IF;
      NEW.payment_confirmed_at := timezone('utc'::text, now());
    ELSE
      RAISE EXCEPTION 'Invalid payment status transition: % -> %', OLD.payment_status, NEW.payment_status;
    END IF;
  END IF;

  -- Rider payout: kitchen owner sends the rider's fee via bKash once the order has
  -- been delivered — BEFORE the customer confirms, per the gate above.
  IF NEW.rider_payout_confirmed IS DISTINCT FROM OLD.rider_payout_confirmed THEN
    IF OLD.rider_payout_confirmed THEN
      RAISE EXCEPTION 'Rider payout has already been confirmed';
    END IF;
    IF NEW.status NOT IN ('delivered', 'completed') THEN
      RAISE EXCEPTION 'Rider can only be marked paid once the order has been delivered';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.kitchens WHERE id = NEW.kitchen_id AND owner_id = auth.uid()) THEN
      RAISE EXCEPTION 'Only the kitchen owner can confirm rider payout';
    END IF;
    NEW.rider_paid_at := timezone('utc'::text, now());
  END IF;

  -- Rider payment confirmation: the rider acknowledges they actually received
  -- the payout the kitchen owner marked as sent — this is the flag that
  -- unblocks the customer's delivery confirmation above, not rider_payout_confirmed.
  IF NEW.rider_payment_confirmed IS DISTINCT FROM OLD.rider_payment_confirmed THEN
    IF OLD.rider_payment_confirmed THEN
      RAISE EXCEPTION 'Rider payment has already been confirmed';
    END IF;
    IF NOT COALESCE(NEW.rider_payout_confirmed, OLD.rider_payout_confirmed) THEN
      RAISE EXCEPTION 'Kitchen owner must mark the rider as paid before the rider can confirm receipt';
    END IF;
    IF auth.uid() <> NEW.rider_id THEN
      RAISE EXCEPTION 'Only the assigned rider can confirm they were paid';
    END IF;
    NEW.rider_payment_confirmed_at := timezone('utc'::text, now());
  END IF;

  -- Receipt issuance: one-shot, only after payment is confirmed
  IF NEW.receipt_issued_at IS DISTINCT FROM OLD.receipt_issued_at THEN
    IF OLD.receipt_issued_at IS NOT NULL THEN
      RAISE EXCEPTION 'Receipt has already been issued for this order';
    END IF;
    IF NEW.payment_status <> 'payment_confirmed' THEN
      RAISE EXCEPTION 'Receipt can only be issued after payment is confirmed';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.kitchens WHERE id = NEW.kitchen_id AND owner_id = auth.uid()) THEN
      RAISE EXCEPTION 'Only the kitchen owner can issue the receipt';
    END IF;
    NEW.receipt_issued_at := timezone('utc'::text, now());
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER enforce_order_assignment
  BEFORE UPDATE ON public.orders
  FOR EACH ROW
  EXECUTE FUNCTION public.check_order_assignment();


-- SECURE RPC TRANSACTION FUNCTIONS

-- Secure Order Placement (insert order, insert order item, create chat).
-- No wallet/payment involved here — payment happens entirely outside the
-- app via bKash after the order exists (see payment_status lifecycle above).
CREATE OR REPLACE FUNCTION public.create_order(
  p_kitchen_id uuid,
  p_menu_item_id uuid,
  p_quantity integer,
  p_delivery_address text,
  p_delivery_latitude numeric,
  p_delivery_longitude numeric
)
RETURNS uuid AS $$
DECLARE
  v_customer_id uuid;
  v_price numeric;
  v_total numeric;
  v_commission numeric;
  v_rider_fee numeric;
  v_order_id uuid;
  v_is_available boolean;
BEGIN
  v_customer_id := auth.uid();
  IF v_customer_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- Get menu item price and availability
  SELECT price, is_available INTO v_price, v_is_available
  FROM public.menu_items
  WHERE id = p_menu_item_id AND kitchen_id = p_kitchen_id;

  IF v_price IS NULL THEN
    RAISE EXCEPTION 'Menu item not found or does not belong to this kitchen';
  END IF;

  IF NOT v_is_available THEN
    RAISE EXCEPTION 'Menu item is not available';
  END IF;

  v_total := v_price * p_quantity;
  v_commission := v_total * 0.10; -- 10% Platform fee
  v_rider_fee := v_total * 0.05;    -- 5% Rider fee

  -- Insert order
  INSERT INTO public.orders (
    customer_id,
    kitchen_id,
    status,
    total_amount,
    commission_amount,
    rider_fee,
    delivery_address,
    delivery_latitude,
    delivery_longitude
  )
  VALUES (
    v_customer_id,
    p_kitchen_id,
    'pending',
    v_total,
    v_commission,
    v_rider_fee,
    p_delivery_address,
    p_delivery_latitude,
    p_delivery_longitude
  )
  RETURNING id INTO v_order_id;
  
  -- Insert order item
  INSERT INTO public.order_items (
    order_id,
    menu_item_id,
    quantity,
    price
  )
  VALUES (
    v_order_id,
    p_menu_item_id,
    p_quantity,
    v_price
  );
  
  -- Create chat row
  INSERT INTO public.chats (order_id)
  VALUES (v_order_id);
  
  RETURN v_order_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- ============================================================================
-- CHAT UPGRADE (additive, idempotent) — read receipts + reply-to
-- Safe to re-run: only ADD COLUMN IF NOT EXISTS / CREATE POLICY guarded by DROP.
-- Does NOT touch the CREATE TABLE / DROP TABLE statements above.
-- ============================================================================
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS read_at TIMESTAMP WITH TIME ZONE;
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS reply_to_message_id UUID REFERENCES public.messages(id);

GRANT UPDATE ON public.messages TO authenticated;

DROP POLICY IF EXISTS "Chat participants can mark messages as read" ON public.messages;
CREATE POLICY "Chat participants can mark messages as read"
  ON public.messages FOR UPDATE TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.chats c
      JOIN public.orders o ON c.order_id = o.id
      WHERE c.id = chat_id AND (
        o.customer_id = auth.uid() OR
        o.rider_id = auth.uid() OR
        EXISTS (SELECT 1 FROM public.kitchens k WHERE k.id = o.kitchen_id AND k.owner_id = auth.uid())
      )
    )
  )
  WITH CHECK (
    -- Only lets a participant mark OTHER people's messages as read, never their own.
    sender_id <> auth.uid() AND
    EXISTS (
      SELECT 1 FROM public.chats c
      JOIN public.orders o ON c.order_id = o.id
      WHERE c.id = chat_id AND (
        o.customer_id = auth.uid() OR
        o.rider_id = auth.uid() OR
        EXISTS (SELECT 1 FROM public.kitchens k WHERE k.id = o.kitchen_id AND k.owner_id = auth.uid())
      )
    )
  );

-- ============================================================================
-- BUGFIX (additive, idempotent): riders could not see unassigned deliveries.
-- The SELECT policy on orders only allowed customer_id/rider_id/kitchen-owner
-- matches, so a rider with no rider_id yet (i.e. before accepting) was
-- silently filtered out by RLS on both plain SELECT and the realtime
-- .stream() subscription that "Available Deliveries Nearby" relies on —
-- the row existed and the kitchen's "awaiting_rider" status was real, the
-- rider's client just never got sent that row at all.
-- Safe to re-run on an existing database: only replaces this one policy.
-- ============================================================================
DROP POLICY IF EXISTS "Users can view their own orders" ON public.orders;
CREATE POLICY "Users can view their own orders"
  ON public.orders FOR SELECT TO authenticated
  USING (
    customer_id = auth.uid() OR
    rider_id = auth.uid() OR
    (status = 'awaiting_rider' AND rider_id IS NULL) OR
    EXISTS (SELECT 1 FROM public.kitchens WHERE id = kitchen_id AND owner_id = auth.uid())
  );


-- REAL-TIME ENABLEMENT
-- Ensure publication is configured for real-time tracking
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
    IF NOT EXISTS (SELECT 1 FROM pg_publication_rel pr JOIN pg_class c ON pr.prrelid = c.oid JOIN pg_publication p ON pr.prpubid = p.oid WHERE p.pubname = 'supabase_realtime' AND c.relname = 'orders') THEN
      ALTER PUBLICATION supabase_realtime ADD TABLE public.orders;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_publication_rel pr JOIN pg_class c ON pr.prrelid = c.oid JOIN pg_publication p ON pr.prpubid = p.oid WHERE p.pubname = 'supabase_realtime' AND c.relname = 'messages') THEN
      ALTER PUBLICATION supabase_realtime ADD TABLE public.messages;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_publication_rel pr JOIN pg_class c ON pr.prrelid = c.oid JOIN pg_publication p ON pr.prpubid = p.oid WHERE p.pubname = 'supabase_realtime' AND c.relname = 'chats') THEN
      ALTER PUBLICATION supabase_realtime ADD TABLE public.chats;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_publication_rel pr JOIN pg_class c ON pr.prrelid = c.oid JOIN pg_publication p ON pr.prpubid = p.oid WHERE p.pubname = 'supabase_realtime' AND c.relname = 'profiles') THEN
      ALTER PUBLICATION supabase_realtime ADD TABLE public.profiles;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_publication_rel pr JOIN pg_class c ON pr.prrelid = c.oid JOIN pg_publication p ON pr.prpubid = p.oid WHERE p.pubname = 'supabase_realtime' AND c.relname = 'kitchens') THEN
      ALTER PUBLICATION supabase_realtime ADD TABLE public.kitchens;
    END IF;
  END IF;
END
$$;
