# Supabase Security Setup Guide

This guide walks you through the manual steps required to secure your Open Listings Map application.

## Step 1: Enable Row Level Security (RLS)

1. **Open Supabase Dashboard**
   - Go to [https://supabase.com/dashboard](https://supabase.com/dashboard)
   - Select your project: `wiufnhadffqkfeiydjzj`

2. **Open SQL Editor**
   - Click the **SQL Editor** icon in the left sidebar
   - Click **New query**

3. **Run Security Policies**
   - Copy the entire contents of [`../sql/supabase_security_policies.sql`](../sql/supabase_security_policies.sql)
   - Paste into the SQL Editor
   - Click **Run** (or press Ctrl+Enter)

4. **Verify Success**
   - You should see a success message
   - The bottom of the query shows a table with your new policy
   - Look for `authenticated_read_only` policy

**What This Does:**
- Enables Row Level Security on `locations_cache` table
- Blocks anonymous access (unauthenticated users get 0 rows)
- Only authenticated users can read data
- Secures the `map_listings_geojson` view

---

## Step 2: Set Up Visited Units Tracking (Optional but Recommended)

This feature allows users to mark which units they've visited with persistent checkboxes.

1. **Open SQL Editor**
   - In Supabase Dashboard, click **SQL Editor**
   - Click **New query**

2. **Run Visited Units Setup**
   - Copy the entire contents of [`../sql/user_visited_units.sql`](../sql/user_visited_units.sql)
   - Paste into the SQL Editor
   - Click **Run**

3. **Verify Success**
   - You should see success messages for:
     - Table created: `user_visited_units`
     - Indexes created
     - RLS enabled
     - Policies created

4. **View the Table**
   - Click **Table Editor** in left sidebar
   - Find `user_visited_units` in the table list
   - Initially empty (users will populate it as they mark units visited)

**What This Does:**
- Creates a table to store which units each user has visited
- Each user can only see/modify their own visited units (RLS enforced)
- Visits are automatically filtered to last 6 months
- Supports multiple users tracking independently

**How Users Will Use It:**
- When viewing a unit popup on the map, check "Visited" checkbox
- Checkbox state persists across sessions and devices
- After 6 months, the unit appears unvisited again (allows re-visiting)
- Visited units are dimmed for easy visual identification

**To View Your Visited Units:**

In Supabase SQL Editor:
```sql
SELECT * FROM user_visited_units
WHERE visited_at > NOW() - INTERVAL '6 months'
ORDER BY visited_at DESC;
```

**Optional: Schedule Automatic Cleanup**

If you want to delete old records (>6 months) from the database entirely:

```sql
-- This is already created by the setup script
-- You can manually run it, or schedule it with pg_cron
SELECT cleanup_old_visited_units();
```

---

## Step 3: Create Team User Accounts

Since you don't want public sign-ups, you'll manually create accounts for each team member.

1. **Navigate to Authentication**
   - In Supabase Dashboard, click **Authentication** (shield icon) in left sidebar
   - Click **Users** tab

2. **Add Each Team Member**
   - Click **Add User** button (top right)
   - Enter their **Email address**
   - Enter a strong **Password** (or generate one)
   - Click **Create User**

3. **Confirm Email (if needed)**
   - If "Auto Confirm" is off, you'll need to manually confirm
   - Click the three dots (⋯) next to the user
   - Select **Confirm email**

4. **Share Credentials Securely**
   - Use a password manager (1Password, Bitwarden)
   - Or send via secure channel (Signal, encrypted email)
   - **Never send passwords in plain text email**

5. **Recommended: First User Setup**
   - Create your own account first
   - Test the login flow works
   - Then create accounts for other team members

**Example Team Setup:**
```
User 1: yourname@company.com (you)
User 2: teammate1@company.com
User 3: teammate2@company.com
...etc
```

---

## Step 4: Test Security Before Deploying

### Test 1: Anonymous Access Should Fail

In Supabase SQL Editor, run:

```sql
-- This should return a count (you're authenticated in the dashboard)
SELECT COUNT(*) FROM public.locations_cache;

-- But when the map.html tries to access without login, it will get 0 rows
```

### Test 2: Verify Policies Are Active

```sql
SELECT 
    tablename,
    policyname,
    roles
FROM pg_policies
WHERE tablename = 'locations_cache';
```

Expected output:
```
tablename         | policyname              | roles
------------------|-------------------------|------------------
locations_cache   | authenticated_read_only | {authenticated}
```

---

## Troubleshooting

### "Permission denied" when running SQL
- Make sure you're the project owner or have admin privileges
- Check you're in the correct project

### Users can't log in
- Verify email confirmation status (Authentication > Users)
- Check password meets requirements (min 6 characters by default)
- Look in Authentication > Logs for error details

### Map shows no data after login
- Check browser console (F12) for errors
- Verify the user is confirmed (not pending)
- Test the SQL query in dashboard while authenticated

### RLS blocks everything (even when logged in)
- Make sure you granted SELECT to `authenticated` role
- Run: `GRANT SELECT ON public.map_listings_geojson TO authenticated;`
- Check the policy uses `TO authenticated` not `TO anon`

---

## Security Notes

✅ **Safe to Commit:**
- The Supabase Anon Key in `map.html` is safe because RLS blocks data access
- Auth tokens are managed by Supabase and never exposed in code

❌ **Never Commit:**
- User passwords
- Your Supabase service role key (not used in this project)
- Any `.env` files with connection strings

🔒 **How Security Works:**
1. User visits `index.html` (login page)
2. User enters credentials
3. Supabase Auth validates and returns a session token
4. Browser stores token in localStorage
5. `map.html` uses token to authenticate API requests
6. Database checks: "Does this token belong to authenticated user?"
7. If yes → Return data | If no → Return empty array

---

## Next Steps

After completing these manual steps:
1. Test login with your newly created user account
2. Verify the map loads data when authenticated
3. Test the logout button works
4. Share credentials with team members

If you need to add more users later, just repeat Step 2.

