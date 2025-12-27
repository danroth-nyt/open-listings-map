# Contact Fields Extraction Guide

## Overview

The Open Listings Map extracts and displays contact information from listing descriptions to help users quickly identify how to access units. This guide documents the extraction logic and field structure.

---

## Fields Added

### 1. `contact` (Phone Number)
**Type:** TEXT  
**Purpose:** Store phone numbers for contacting about the unit

**Solil Source:**
- Extracted from `contact` field
- Falls back to `url` field if it contains a phone number
- Cleans up trailing symbols (©, ®, (L))

**UWS Source:**
- Extracted from `description` field using multiple patterns:
  - "showings [Name]: [phone]"
  - "contact [Name] at [phone]"
  - "call [Name] at [phone]"
  - "To View: [Name] [phone]"
  - "super [name] [7-digit]"
  - Any 10-digit or 7-digit phone number

**Formats Supported:**
- `(XXX) XXX-XXXX`
- `XXX-XXX-XXXX`
- `XXX.XXX.XXXX`
- `XXX XXX XXXX`
- `XXX-XXXX` (7-digit local)

**Display:**
- Teal box with phone icon (📞)
- Clickable `tel:` link on mobile devices
- Format: `XXX-XXX-XXXX`

### 2. `contact_name` (Person's Name)
**Type:** TEXT  
**Purpose:** Identify who to contact (Super, Doorman, specific person)

**Solil Source:**
- Extracted from `super` field

**UWS Source:**
- Extracted from `description` field:
  - "Keys with Superintendent [Name]"
  - "Keys with Super [Name]"
  - "Keys with Handyman" → "Handyman"
  - "Keys with doorman" → "Doorman"
  - "showings [Name]:"

**Display:**
- Purple box with person icon (👤)
- Shows name exactly as extracted

### 3. `keys_access` (Access Instructions)
**Type:** TEXT  
**Purpose:** Provide instructions on how to get keys to view the unit

**Solil Source:**
- Not available (set to NULL)

**UWS Source:**
- Extracted from `description` field:
  - "Keys with [details]" (full instruction)
  - "KEYBOX [number]" → "Keybox [number]"

**Display:**
- Orange box with key icon (🔑)
- Shows full instruction text

---

## Extraction Patterns

### Phone Number Patterns

```regex
# 10-digit with optional parentheses and separators
\(?[0-9]{3}\)?[-.\s]*[0-9]{3}[-.\s]*[0-9]{4}

# 7-digit local number
\b[0-9]{3}[-.\s]*[0-9]{4}\b
```

### Contact Name Patterns

```regex
# Superintendent with name
Keys with Superintendent\s+([A-Za-z\s]+)

# Super with name
Keys with Super\s+([A-Za-z\s]+)

# Generic doorman
Keys with (the )?doorman

# Showings contact
showings?\s+([A-Za-z\s]+):
```

### Keys Access Patterns

```regex
# Full keys instruction
Keys with [^.|]+

# Keybox code
KEYBOX\s+[0-9]+
```

---

## Data Quality

### Coverage by Source

| Source | Contact Phone | Contact Name | Keys Access |
|--------|--------------|--------------|-------------|
| Solil  | 100% (447/447) | 100% (super field) | 0% (not available) |
| UWS    | 28% (348/1236) | ~40% (estimated) | ~60% (estimated) |

### UWS Limitations

Many UWS listings have poor contact data quality:
- Phone numbers not consistently formatted
- Names embedded in unstructured text
- Some listings have no contact information at all

**Improvement Opportunities:**
1. Add more extraction patterns as new formats are discovered
2. Build a lookup table for building management contacts
3. Cross-reference with external data sources

---

## Usage in Map

Each listing popup card displays available fields in this order:

```
┌─────────────────────────────┐
│ Unit 3A                 NEW │ ← Header with status
├─────────────────────────────┤
│ $3,500                      │ ← Rent
│ 2 Beds · 1 Bath            │ ← Details
│ 👤 Super: John Smith       │ ← Contact Name (purple)
│ 📞 212-555-1234            │ ← Phone (teal, clickable)
│ 🔑 Keys with Doorman       │ ← Keys Access (orange)
│ Source: UWS                 │ ← Source
└─────────────────────────────┘
```

**Behavior:**
- Fields only appear if data is available
- Phone numbers are clickable on mobile
- All fields use icon + colored box styling
- Text is escaped to prevent XSS

---

## Database Schema

### View Definition

```sql
CREATE VIEW marts.unified_listings_vw AS
SELECT
  -- ... other fields ...
  contact,        -- Phone number (formatted)
  contact_name,   -- Person's name
  keys_access,    -- Access instructions
  -- ... other fields ...
FROM source_tables
```

### GeoJSON Properties

```javascript
{
  "properties": {
    "address": "123 Main St",
    "unit": "3A",
    "rent": "$3,500",
    "bed": "2",
    "bath": "1",
    "source": "UWS",
    "contact": "212-555-1234",      // NEW
    "contactName": "John Smith",    // NEW
    "keysAccess": "Keys with Doorman", // NEW
    "status": "addition"
  }
}
```

---

## Updating the View

To modify the extraction logic:

1. Update the SQL view in Supabase:
   ```sql
   DROP VIEW IF EXISTS public.map_listings_geojson CASCADE;
   DROP VIEW IF EXISTS marts.unified_listings_vw CASCADE;
   -- Create updated views with new extraction logic
   ```

2. Test extraction with sample data:
   ```sql
   SELECT 
     description,
     contact,
     contact_name,
     keys_access
   FROM marts.unified_listings_vw
   WHERE source_name = 'UWS'
   LIMIT 50;
   ```

3. Update the view definition (see `sql/update_unified_listings_with_contact.sql`)

4. Refresh the map in browser (no code changes needed)

---

## Testing

### Verify Contact Extraction

```sql
-- Check extraction coverage
SELECT 
  source_name,
  COUNT(*) as total_listings,
  COUNT(contact) as with_phone,
  COUNT(contact_name) as with_name,
  COUNT(keys_access) as with_keys,
  ROUND(100.0 * COUNT(contact) / COUNT(*), 1) as phone_pct
FROM marts.unified_listings_vw
GROUP BY source_name;
```

### Find Missing Contacts

```sql
-- Find UWS listings with numbers in description but no contact extracted
SELECT 
  address,
  unit_number,
  description_combined
FROM marts.unified_listings_vw
WHERE source_name = 'UWS'
  AND contact IS NULL
  AND description_combined ~ '[0-9]{3}'
LIMIT 20;
```

### Validate Phone Format

```sql
-- Check for malformed phone numbers
SELECT 
  contact,
  COUNT(*) as count
FROM marts.unified_listings_vw
WHERE contact IS NOT NULL
  AND NOT contact ~ '^\d{3}-\d{3,4}-\d{4}$'
GROUP BY contact
ORDER BY count DESC;
```

---

## Troubleshooting

### No contacts showing in map

**Cause:** View not updated or data not extracted  
**Fix:** Re-run the view creation SQL in Supabase

### Phone numbers not clickable

**Cause:** Format not detected as phone pattern  
**Fix:** Check JavaScript regex in map.html line ~706

### Contact name shows "null"

**Cause:** Field is displaying literal null instead of hiding  
**Fix:** JavaScript checks `if (unit.contactName)` should prevent this

### Keys access too long

**Cause:** Full description extracted instead of just keys instruction  
**Fix:** Adjust regex to stop at first period or pipe character

---

## Future Enhancements

1. **Email Extraction:** Add pattern to extract email addresses
2. **Website Links:** Extract and validate URLs
3. **Building Lookup:** Create table mapping buildings to management contacts
4. **AI Enhancement:** Use GPT to extract structured contact data
5. **Manual Overrides:** Allow admin to manually set contact info

---

## Related Files

- `sql/update_unified_listings_with_contact.sql` - View creation SQL
- `map.html` - Frontend display logic (lines 701-745)
- `README.md` - Main documentation
- Database: `marts.unified_listings_vw`, `public.map_listings_geojson`

---

**Last Updated:** December 27, 2025  
**Version:** 1.1  
**Branch:** `feature/google-maps-integration`  
**Status:** ✅ Production Ready

## Recent Updates

### December 27, 2025
- Enhanced popup readability with forced light theme colors
- Improved dark mode compatibility
- Optimized font loading for better performance

### December 22, 2025
- Initial implementation of contact field extraction
- Added display logic in map popups
- Created extraction patterns for UWS and Solil sources

