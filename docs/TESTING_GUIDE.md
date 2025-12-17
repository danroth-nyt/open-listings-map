# Authentication & Security Testing Guide

This guide provides step-by-step instructions to test the complete authentication flow and verify Row Level Security is working correctly.

## Pre-Testing Checklist

Before you begin testing, ensure you've completed:

- [ ] Ran `supabase_security_policies.sql` in Supabase SQL Editor
- [ ] Created at least one test user account in Supabase Dashboard (Authentication > Users)
- [ ] Confirmed the user's email (if auto-confirm is disabled)
- [ ] Updated Supabase credentials in both `index.html` and `map.html`
- [ ] Have a modern web browser with Developer Tools available (Chrome, Firefox, Edge)

## Test 1: Row Level Security (Database Level)

**Purpose**: Verify that RLS policies are correctly blocking anonymous access.

### Steps:

1. Open Supabase Dashboard → SQL Editor
2. Run this query:

```sql
-- Check that RLS is enabled
SELECT schemaname, tablename, rowsecurity 
FROM pg_tables 
WHERE tablename = 'locations_cache';
```

**Expected Result**: `rowsecurity` column should be `true`

3. Verify the policy exists:

```sql
SELECT tablename, policyname, roles, cmd 
FROM pg_policies 
WHERE tablename = 'locations_cache';
```

**Expected Result**: Should show `authenticated_read_only` policy for `authenticated` role

4. Test that you (authenticated in dashboard) can see data:

```sql
SELECT COUNT(*) FROM public.locations_cache;
```

**Expected Result**: Should return the actual count of cached locations (not 0)

5. Verify anonymous access is revoked:

```sql
SELECT grantee, privilege_type 
FROM information_schema.role_table_grants 
WHERE table_name = 'locations_cache';
```

**Expected Result**: Should NOT show `anon` role with SELECT privilege

### ✅ Test 1 Pass Criteria:
- RLS is enabled on `locations_cache`
- Policy exists and targets `authenticated` role
- Data is visible in SQL Editor (authenticated context)
- Anonymous role has no SELECT privileges

---

## Test 2: Login Page Functionality

**Purpose**: Verify the login page renders correctly and handles authentication.

### Steps:

1. **Open Login Page**
   - Navigate to `index.html` in your browser
   - Open Developer Tools (F12) → Console tab

2. **Verify Page Elements**
   - [ ] Modern login form is visible (not redirect message)
   - [ ] Email input field present
   - [ ] Password input field present
   - [ ] "Remember me" checkbox present
   - [ ] "Sign In" button present
   - [ ] No JavaScript errors in console

3. **Test Invalid Credentials**
   - Enter email: `wrong@example.com`
   - Enter password: `wrongpassword`
   - Click "Sign In"
   
   **Expected Result**: 
   - Error message displays: "Invalid email or password"
   - Page does NOT redirect
   - Button text returns to "Sign In"

4. **Test Empty Fields**
   - Leave email blank
   - Click "Sign In"
   
   **Expected Result**: 
   - Browser validation error (HTML5 required attribute)

5. **Test Valid Credentials**
   - Enter your test user email
   - Enter the correct password
   - **UNCHECK** "Remember me"
   - Click "Sign In"
   
   **Expected Result**:
   - Button text changes to "Success! Redirecting..."
   - Console shows: `Login successful!`
   - Redirects to `map.html` within 1 second
   - Map loads and displays data

### ✅ Test 2 Pass Criteria:
- Login page renders modern form
- Invalid credentials show error without redirect
- Valid credentials successfully redirect to map
- No console errors during login process

---

## Test 3: Authentication Guard on Map Page

**Purpose**: Verify that unauthenticated users cannot access the map directly.

### Steps:

1. **Clear Browser Session**
   - Open Developer Tools (F12) → Application/Storage tab
   - Navigate to Local Storage → your domain
   - Delete all Supabase auth entries (starting with `sb-`)
   - OR use Incognito/Private browsing mode

2. **Attempt Direct Access**
   - Navigate directly to `map.html` URL
   - Watch the browser behavior
   
   **Expected Result**:
   - Should immediately redirect to `index.html`
   - Console shows: `No active session found, redirecting to login...`
   - Map does NOT render
   - No data is loaded

3. **Login and Access Map**
   - Login via `index.html` with valid credentials
   - Verify you're redirected to `map.html`
   - Map should load successfully

4. **Refresh Map Page**
   - Press F5 or Ctrl+R to refresh
   
   **Expected Result**:
   - If "Remember me" was checked: Map stays loaded
   - If "Remember me" was NOT checked: May redirect to login (session expired)

### ✅ Test 3 Pass Criteria:
- Direct access to map without login redirects to login page
- No map data is exposed to unauthenticated users
- Authenticated users can access and refresh the map

---

## Test 4: Data Access with Authentication

**Purpose**: Verify that authenticated users can fetch data via the API.

### Steps:

1. **Login Successfully**
   - Login via `index.html`
   - Navigate to `map.html`

2. **Check Network Requests**
   - Open Developer Tools (F12) → Network tab
   - Look for requests to `supabase.co` domain
   - Find the request to `map_listings_geojson`
   - Click on it to inspect

3. **Verify Request Headers**
   - Check the request headers
   - Should include: `Authorization: Bearer <token>`
   - The token proves authentication

4. **Verify Response**
   - Check the response body
   - Should return JSON array with listing data
   - Status code: 200 OK
   
   **Expected Result**:
   - Data is returned successfully
   - Map displays points
   - Console shows: `Found X listings`
   - Console shows: `Successfully loaded X listings on map`

5. **Test with Invalid Token (Advanced)**
   - In Console tab, run:
   
   ```javascript
   // Clear the session
   await supabaseClient.auth.signOut();
   ```
   
   - Try to fetch data manually:
   
   ```javascript
   const { data, error } = await supabaseClient
     .from('map_listings_geojson')
     .select('feature')
     .limit(5);
   console.log('Data:', data, 'Error:', error);
   ```
   
   **Expected Result**:
   - Should return empty array or RLS policy error
   - Should redirect to login page

### ✅ Test 4 Pass Criteria:
- Authenticated requests include Bearer token
- API returns data successfully
- Map displays points correctly
- Unauthenticated requests return no data

---

## Test 5: Logout Functionality

**Purpose**: Verify logout clears session and redirects to login.

### Steps:

1. **Login and Access Map**
   - Login via `index.html`
   - Verify map loads

2. **Click Logout Button**
   - Find the "Logout" button in the bottom-right legend
   - Click it
   
   **Expected Result**:
   - Console shows: `User logged out successfully`
   - Redirects to `index.html`
   - Session is cleared

3. **Verify Session Cleared**
   - Open Developer Tools → Application/Storage → Local Storage
   - Check for Supabase auth entries
   
   **Expected Result**:
   - Auth tokens should be cleared
   - Session data should be removed

4. **Attempt to Return to Map**
   - Try navigating back to `map.html`
   
   **Expected Result**:
   - Should redirect to login page
   - Cannot access map without re-authenticating

### ✅ Test 5 Pass Criteria:
- Logout button successfully clears session
- User is redirected to login page
- Cannot access map after logout without re-login

---

## Test 6: Remember Me Functionality

**Purpose**: Verify session persistence based on "Remember me" checkbox.

### Steps:

1. **Test WITHOUT Remember Me**
   - Login with "Remember me" UNCHECKED
   - Note the time
   - Keep browser open for 2+ hours (or check localStorage for token expiry)
   
   **Expected Result**:
   - Session expires after ~1 hour
   - Next map access requires re-login

2. **Test WITH Remember Me**
   - Logout
   - Login again with "Remember me" CHECKED
   - Close browser completely
   - Reopen browser and navigate to `map.html`
   
   **Expected Result**:
   - Session persists (up to 7 days)
   - Map loads without requiring login
   - No redirect to login page

3. **Check Token in Storage**
   - Open Developer Tools → Application/Storage → Local Storage
   - Find Supabase auth entries
   - Look for expiration timestamps
   
   **Expected Result**:
   - With "Remember me": expires_at is ~7 days in future
   - Without "Remember me": expires_at is ~1 hour in future

### ✅ Test 6 Pass Criteria:
- Unchecked "Remember me" results in shorter session (~1 hour)
- Checked "Remember me" results in longer session (~7 days)
- Session persists across browser restarts when "Remember me" is checked

---

## Test 7: Session Timeout (30 Minute Inactivity)

**Purpose**: Verify inactive sessions automatically logout after 30 minutes.

### Steps:

1. **Login Successfully**
   - Login via `index.html`
   - Access `map.html`

2. **Remain Inactive**
   - Do NOT move mouse, type, or interact with page
   - Wait 28 minutes (or adjust SESSION_TIMEOUT_MS in code for faster testing)

3. **Warning Dialog Appears**
   - At 28 minutes (2 minutes before timeout), a warning dialog should appear
   
   **Expected Result**:
   - Dialog says: "Your session will expire in 2 minutes due to inactivity"
   - Options: OK (stay logged in) or Cancel (logout now)

4. **Test "Stay Logged In" Option**
   - Click "OK" in the warning dialog
   
   **Expected Result**:
   - Timeout resets
   - Can continue using the map
   - Warning will appear again after 28 more minutes of inactivity

5. **Test Auto-Logout**
   - Remain inactive through the warning (don't click anything)
   - Wait 2 more minutes
   
   **Expected Result**:
   - Alert appears: "Your session has expired due to inactivity"
   - Redirects to login page
   - Session is cleared

6. **Test Activity Resets Timeout**
   - Login again
   - After 10 minutes, move the mouse or scroll
   - Wait another 28 minutes
   
   **Expected Result**:
   - Timeout resets with each interaction
   - Warning appears 28 minutes after LAST activity

### ✅ Test 7 Pass Criteria:
- Warning appears 2 minutes before timeout
- "Stay logged in" resets the timer
- Auto-logout occurs after full timeout period
- Mouse/keyboard activity resets the timeout timer

---

## Test 8: Browser Console Monitoring

**Purpose**: Verify proper logging and no errors during normal operation.

### Steps:

1. **Open Console**
   - Open Developer Tools (F12) → Console tab
   - Clear console

2. **Complete Full User Journey**
   - Navigate to `index.html`
   - Login with valid credentials
   - Wait for map to load
   - Click on a map point
   - Click logout

3. **Review Console Messages**

**Expected Console Log Sequence**:

```
Checking session...
No active session found (OR Existing session found, redirecting to map...)
[After login:]
Login successful!
[On map page:]
Authentication verified, initializing map...
User authenticated: user@example.com
Starting to fetch listings...
Fetch complete. Data: [...]
Found X listings
GeoJSON built: [...]
Adding data to map...
Successfully loaded X listings on map
[After logout:]
User logged out successfully
```

4. **Check for Errors**
   - Should see NO red error messages
   - Should see NO 403 Forbidden errors
   - Should see NO "RLS policy violation" errors

### ✅ Test 8 Pass Criteria:
- Console shows clear authentication flow
- No errors during login/logout cycle
- Data fetches successfully
- Map renders without errors

---

## Test 9: Cross-Browser Compatibility

**Purpose**: Verify authentication works across different browsers.

### Browsers to Test:
- [ ] Google Chrome
- [ ] Mozilla Firefox
- [ ] Microsoft Edge
- [ ] Safari (if on Mac)

### For Each Browser:
1. Navigate to `index.html`
2. Login with valid credentials
3. Verify map loads
4. Logout
5. Check for console errors

**Expected Result**: Authentication should work identically across all modern browsers.

---

## Test 10: Security Verification (Final Check)

**Purpose**: Confirm that security measures are in place and functioning.

### Checklist:

- [ ] **Unauthenticated users cannot see data**
  - Test: Clear cookies, try to access map directly
  - Result: Redirects to login, no data exposed

- [ ] **RLS blocks anonymous API calls**
  - Test: Make API call without auth token
  - Result: Returns 0 rows or RLS error

- [ ] **Session tokens expire**
  - Test: Wait for session expiration
  - Result: Redirects to login after timeout

- [ ] **Logout clears sensitive data**
  - Test: Check localStorage after logout
  - Result: Auth tokens removed

- [ ] **API keys are safe to expose**
  - Check: Supabase Anon Key is in client-side code
  - Verify: RLS prevents data access even with the key

- [ ] **No passwords in source code**
  - Check: Search codebase for plaintext passwords
  - Result: Only configuration, no credentials

### ✅ Test 10 Pass Criteria:
- All security measures are active and functioning
- Data is protected at database level
- Sessions are properly managed and expire
- No sensitive data exposed in code or storage

---

## Common Issues & Solutions

### Issue: "Invalid login credentials" with correct password
**Solution**: 
- Verify user email is confirmed in Supabase Dashboard
- Check for typos in email address
- Try resetting password in Supabase Dashboard

### Issue: Map shows no data after successful login
**Solution**:
- Verify RLS policies are created correctly
- Check policy grants SELECT to `authenticated` role
- Ensure `locations_cache` has data
- Check browser console for specific error messages

### Issue: Session expires immediately after login
**Solution**:
- Verify browser allows localStorage
- Check for browser extensions blocking storage
- Try incognito/private mode to rule out extensions

### Issue: Redirect loop (keeps bouncing between pages)
**Solution**:
- Clear all browser data (cache, cookies, localStorage)
- Verify Supabase URL is identical in both HTML files
- Check console for authentication state change errors

### Issue: Timeout warning appears too quickly/slowly
**Solution**:
- Adjust `SESSION_TIMEOUT_MS` in `map.html` (line ~148)
- Default is 30 minutes (30 * 60 * 1000)
- For testing, use 2 minutes (2 * 60 * 1000)

---

## Testing Completion Checklist

Mark each test as completed:

- [ ] Test 1: Row Level Security verified
- [ ] Test 2: Login page functionality confirmed
- [ ] Test 3: Authentication guard working
- [ ] Test 4: Data access with auth successful
- [ ] Test 5: Logout functionality working
- [ ] Test 6: Remember me feature working
- [ ] Test 7: Session timeout working
- [ ] Test 8: Console logs clean, no errors
- [ ] Test 9: Cross-browser compatibility verified
- [ ] Test 10: Security measures confirmed

**All tests passed?** Your authentication system is fully functional and secure! 🎉

---

## Production Deployment Notes

Before deploying to production:

1. **Create real user accounts** for your team in Supabase Dashboard
2. **Share credentials securely** (use password manager, not email)
3. **Document the login URL** for team members
4. **Set up monitoring** for failed login attempts in Supabase Dashboard
5. **Test from production URL** (not localhost) to verify CORS and domain settings
6. **Verify RLS policies** are active in production Supabase project
7. **Consider setting up custom domain** for professional appearance

**Security Reminder**: The Supabase Anon Key is safe to expose because RLS prevents data access. However, NEVER expose the Supabase Service Role Key.

