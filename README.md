🚴 README — RIDER APP
📌 Overview

The Rider App allows delivery riders to see orders assigned to them and update status in real-time.
Works automatically when admin assigns a rider in the Admin App.

Built with Flutter + Supabase Realtime.

✨ Rider Features
🛵 View Assigned Orders

Shows only orders where:

rider_id = auth.uid()


Displays:

pickup/delivery address

service type

payment method

pickup & delivery schedule

🔄 Status Update Flow

A single button advances the order through:

accepted

picked_up

in_wash

in_delivery

completed

The button changes automatically based on current status.

🔔 Real-Time Updates

When admin assigns an order → rider sees it instantly

When admin edits status → rider sees it instantly

🔃 Refresh Button

Manual refresh using pull-to-refresh

reloads all assigned orders

🚪 Logout

Rider can log out anytime

🗄 Database Tables Used
profiles

Rider must have:

role = 'rider'

laundry_orders

Fields used in rider app:

rider_id

pickup_address

delivery_address

service

payment_method

status

timestamps

🔐 Supabase RLS Policies for Rider

Rider can only see/update orders assigned to them:

create policy "rider_select_assigned"
on laundry_orders
for select
using (auth.uid() = rider_id);

create policy "rider_update_assigned"
on laundry_orders
for update
using (auth.uid() = rider_id)
with check (auth.uid() = rider_id);


Riders cannot delete or modify other users’ orders.

▶️ How to Run Rider App
1. Install dependencies
   flutter pub get

2. Configure Supabase (supabase_config.dart)
   await Supabase.initialize(
   url: "https://<SUPABASE-PROJECT>.supabase.co",
   anonKey: "<ANON-KEY>",
   );

3. Run Rider App
   flutter run


Rider will see only assigned orders.