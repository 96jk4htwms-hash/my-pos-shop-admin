# Smart POS Pro V7.02 JavaScript

V7.01 เดิมยังคง inline runtime เพื่อความเข้ากันได้
V7.02 เพิ่ม bridge modules ที่โหลดต่อท้าย runtime เดิม:

- `core/v702-config.js`
- `core/v702-utils.js`
- `features/v702-image-checker.js`
- `features/v702-import-safety.js`
- `services/v702-supabase-import.js`
- `features/v7021-hardening.js`
- `features/v7022-docs-hub.js` — unified "เอกสารและธุรกรรม" summary/export tab
  (adds a 3rd tab inside the existing Documents page; reads db.bills/cashLedger/
  documents + the last import plan, no new schema)

หลักการ:
1. ไม่แทนที่ Import Center เดิมทันที
2. เพิ่มความปลอดภัยและ recovery plan แบบ additive
3. Supabase Import Center จะเขียนข้อมูลเมื่อมี authenticated user เท่านั้น
4. ถ้าไม่มี Auth ระบบ Import เดิมยังทำงานต่อ และเก็บแผนใน localStorage
