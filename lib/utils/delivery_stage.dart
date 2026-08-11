/// Order statuses from which the customer's live location and contact
/// details (name, phone) become visible to the assigned rider — only once
/// the food has actually been picked up from the kitchen, never before.
const Set<String> customerContactUnlockedStatuses = {
  'picked_up',
  'on_the_way',
  'arrived',
  'delivered',
};

/// Whether a rider should be able to see the customer's live location and
/// contact details for an order currently at [status].
bool isCustomerContactUnlocked(String? status) =>
    customerContactUnlockedStatuses.contains(status);

/// Order statuses from which the assigned rider's personal bKash number
/// becomes visible to the kitchen owner — also from pickup onward, but
/// (unlike [customerContactUnlockedStatuses]) still true once 'completed',
/// since that's exactly when the owner needs it to pay the rider.
const Set<String> riderContactUnlockedStatuses = {
  'picked_up',
  'on_the_way',
  'arrived',
  'delivered',
  'completed',
};

/// Whether the kitchen owner should be able to see the rider's bKash number
/// for an order currently at [status].
bool isRiderContactUnlocked(String? status) =>
    riderContactUnlockedStatuses.contains(status);
