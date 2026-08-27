# SmartPOS V7.02.1 Integrated Fix

แก้จาก `pos1.zip` โดยคง Import Engine V7.01 เดิมไว้ และเพิ่ม Hardening Layer

## แก้หลัก
- เพิ่ม `v7021-hardening.js`
- Fuzzy match >= 92% เป็น REVIEW/SKIP ก่อน ไม่ auto-update
- ตรวจรูปแบบ concurrency 6 รายการ
- มีปุ่ม `ตรวจรูปทั้งหมด`
- URL รูป BAD/BLOCKED จะไม่ทับรูปเดิมอัตโนมัติ
- เก็บ local recovery plan
- เปลี่ยน schema/version เป็น V7.02.1
- Service Worker cache เป็น V7.02.1
- แยก RESET SQL เป็น DEVELOPMENT ONLY
- เพิ่ม `SMARTPOS_PRODUCTION_V7_02_1.sql` สำหรับ migration แบบไม่ DROP ตารางสินค้า

## วิธีใช้
1. Backup Supabase
2. รัน `SMARTPOS_PRODUCTION_V7_02_1.sql`
3. ทดสอบ Login/Sync
4. เปิด Import แล้วตรวจรูป
5. ทดสอบ 5-20 รายการก่อน
6. ตรวจ ADD/UPDATE/SKIP และ Diff
7. จึงค่อยนำเข้าไฟล์เต็ม `SmartPOS_Stock.xlsx`

## สำคัญ
Supabase Import Center เป็น optional persistence และต้องมี authenticated Supabase user ตาม policy; ระบบ POS local import เดิมยังทำงานได้โดยไม่ต้องใช้ส่วนนี้.
ห้ามใช้ `SMARTPOS_DEVELOPMENT_RESET_ONLY.sql` กับฐานข้อมูลร้านจริง.

## Patch (post-release code review)
- แก้ `pendingImportData` จาก `let` เป็น `var` — ของเดิม `window.pendingImportData` เป็น `undefined` เสมอ ทำให้ `v702-import-safety.js`/`v7021-hardening.js` (ตรวจรูป, fuzzy review, ป้องกันรูปเสียทับรูปเดิม, local recovery plan) **ไม่เคยทำงานจริง** ตั้งแต่ V7.02
- แก้ปุ่ม "ยืนยันนำเข้า" เงื่อนไข show/hide กลับด้าน (ปุ่มหายตอนมีของให้นำเข้า, โผล่ตอนไม่มี) — เป็น regression จาก `index.original.html`
- เชื่อม `SmartPOSV702SupabaseImport` (`createBatch/saveItems/finalize`) เข้ากับ event `logTransaction('PRODUCT_IMPORT', ...)` จริง — ก่อนหน้านี้ schema/SQL/service ถูกสร้างไว้แต่ไม่มีจุดใดเรียกใช้เลย
- ลบ `SMARTPOS_PRODUCTION_V7_02_LEGACY.sql` ออก เพราะเนื้อหาเหมือนกับ `SMARTPOS_PRODUCTION_V7_02_1.sql` ทุกตัวอักษร (ไม่ใช่ legacy จริง อาจทำให้เลือกไฟล์ผิดตอน migrate) — ถ้าต้องการเก็บสคีมาเวอร์ชันก่อนหน้าไว้จริง ให้ backup จากที่รันบน Supabase ของร้านเองแทน
- อัปเดต label เวอร์ชันใน SQL header และ UI (เดิมค้างที่ "V7.02"/"V7.01") ให้ตรงกับ V7.02.1
- แก้ SQL: `error_logs` เดิมใช้ `CREATE TABLE IF NOT EXISTS` เฉยๆ ซึ่งถ้าตารางนี้มีอยู่แล้วจากเวอร์ชันเก่า (schema ไม่มีคอลัมน์ `created_by`) จะไม่เติมคอลัมน์ให้ ทำให้ `CREATE POLICY` ที่อ้าง `created_by` พังด้วย error `column "created_by" does not exist` — เปลี่ยนให้ใช้ `DO $$ IF to_regclass(...) ... ELSE ALTER TABLE ADD COLUMN IF NOT EXISTS ... END $$` แบบเดียวกับ `audit_log` ที่ทำถูกอยู่แล้ว
- แก้ SQL: `audit_log` เอง (ตารางที่ "ทำถูกอยู่แล้ว" ด้านบน) จริงๆ แล้วยังพลาดเหมือนกัน — กิ่ง ELSE (กรณีตารางมีอยู่ก่อน) ลืมเติมคอลัมน์ `ts`, `action`, `actor` ทำให้ `CREATE INDEX idx_audit_log_ts ON audit_log(ts)` และ `idx_audit_log_action` พังด้วย error `column "ts" does not exist` กับฐานที่มีตาราง `audit_log` เก่าอยู่ก่อน — เพิ่มคอลัมน์ที่ขาดเข้าไปในกิ่ง ELSE ครบแล้ว

### แก้บั๊กด่วน: นำเข้าไฟล์ Excel ทำบาร์โค้ด/รหัสสินค้าเลข 0 นำหน้าหาย
เดิมอ่านไฟล์ Excel ด้วย `XLSX.utils.sheet_to_json(sheet, {header:1})` ซึ่งค่า default จะดึง **ค่าตัวเลขดิบ** ของเซลล์ ไม่ใช่ข้อความที่เห็นในหน้าจอ Excel — ถ้าคอลัมน์บาร์โค้ด/รหัสสินค้าถูกจัดรูปแบบเป็นตัวเลขแบบเติมศูนย์นำหน้า (เช่น format "0000000000000" เพื่อให้โชว์ "0891234567890") ตัวเลขที่ไฟล์เก็บจริงคือ `891234567890` (ไม่มีเลข 0 นำหน้า) — พอระบบแปลงเป็นข้อความด้วย `.toString()` เลข 0 นำหน้าจึงหายไปเงียบๆ ทำให้บาร์โค้ดผิด จับคู่กับสินค้าเดิมไม่ได้ กลายเป็นสร้างสินค้าใหม่ซ้ำ หรือฟ้อง "บาร์โค้ดชนกับสินค้าอื่น" ทั้งที่จริงๆ คือสินค้าเดียวกัน

แก้โดยเพิ่ม `raw:false` (อ่านค่าตามที่แสดงในหน้าจอ Excel จริง แทนค่าตัวเลขดิบ) — ตัวเลขราคา/ทุน/สต็อกยังอ่านถูกต้องเหมือนเดิม เพราะ `parseImportNumber()` มีการตัด comma คั่นหลักพันออกก่อนแปลงเป็นตัวเลขอยู่แล้ว

**คำแนะนำเสริม**: เพื่อความชัวร์ 100% แนะนำให้ตั้งคอลัมน์บาร์โค้ด/รหัสสินค้าในไฟล์ Excel เป็นรูปแบบ **Text** (ไม่ใช่ Number) ตั้งแต่ตอนกรอกข้อมูล — Excel จะไม่พยายามตีความเป็นตัวเลขตั้งแต่ต้น ปลอดภัยที่สุดไม่ว่าโปรแกรมฝั่งไหนจะอ่านยังไง
แอปนี้**ไม่เคยมีการ login เข้า Supabase Auth เลย** (ใช้แค่ anon key ต่อ client อย่างเดียว) แต่ RLS policy ของ storage (`product-images`) และตารางใหม่ทั้งหมดที่ migration นี้เพิ่ม (`import_batches`, `import_items`, `import_changes`, `import_snapshots`, `audit_log`, `error_logs`) ถูกกำหนดเป็น `TO authenticated` ซึ่งต้องมี `auth.uid()` จริงเท่านั้น — ผลคือทุกครั้งที่พยายามอัปโหลดรูปหรือบันทึกอะไรลงตารางเหล่านี้ **จะถูก RLS ปฏิเสธเงียบๆ ทุกครั้ง ตั้งแต่เริ่มมีตารางนี้** (ไม่ใช่ปัญหาที่เพิ่งเกิด)

แก้โดยเพิ่มการ **login แบบ anonymous อัตโนมัติ** (`supabase.auth.signInAnonymously()`) ทันทีที่สร้าง client — ไม่ต้องมีหน้า login เพิ่ม ผู้ใช้ไม่รู้สึกอะไรเลย แต่ auth.uid() จะมีค่าจริงถาวรต่อเครื่อง/เบราว์เซอร์ ทำให้ policy ที่ตั้งใจออกแบบไว้ทำงานได้จริง (`js/core` ของ `index.html` ส่วน `getSupabaseClient`)

เพิ่ม `documents` storage bucket + policy ที่ขาดหายไปเลย (โค้ดอ้างถึงแต่ไม่เคยมี SQL สร้าง bucket นี้)

เพิ่ม timeout 25 วินาทีให้การอัปโหลดทั้งสองจุด (`uploadProductImageToSupabase`, `uploadGenericFileToSupabase`) ถ้าเน็ตค้างจริงๆ จะฟ้อง error ชัดเจนแทนการค้างเงียบไม่จำกัดเวลา

**สิ่งที่ต้องทำในฝั่ง Supabase Dashboard ก่อนใช้งานได้จริง:**
Authentication → Settings/Providers → เปิด **"Allow anonymous sign-ins"** ให้เป็น ON (โปรเจกต์ใหม่บางอันปิดไว้เป็นค่าเริ่มต้น) ถ้าไม่เปิด ระบบจะยัง error แต่คราวนี้จะขึ้นข้อความชัดเจนใน console แทนที่จะค้างเฉยๆ

### แก้เพิ่ม: "อัปโหลดรูปไม่สำเร็จ — new row violates row-level security policy"
error นี้เกิดเพราะ toggle "Allow anonymous sign-ins" (ข้างบน) ยังไม่ได้เปิดในโปรเจกต์ Supabase ของร้าน — เพื่อไม่ให้ต้องพึ่ง toggle นี้ (บางโปรเจกต์อาจไม่มีสิทธิ์เปิด หรือเปิดไม่ได้ในบางแพ็กเกจ) จึงปรับ policy ของ Storage (`product-images` และ `documents`) จาก `TO authenticated` เป็น `TO anon, authenticated` — เพราะ policy กลุ่มนี้เช็คแค่ `bucket_id` ไม่ได้ผูกกับ `auth.uid()` จึงเปิดให้ anon role (คือ client ที่ใช้แค่ anon key โดยไม่ได้ login เลย) เขียนได้อย่างปลอดภัย โดยไม่กระทบตารางอื่นที่ผูก `owner_id = auth.uid()` ไว้ (import_batches, audit_log, error_logs — กลุ่มนี้ยังต้องเปิด anonymous sign-in อยู่ดีถ้าอยากให้ทำงาน)
