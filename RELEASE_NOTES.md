# Smart POS Pro V7.01 — Import Safety + PWA

## นำเข้าสินค้าด่วน
- เพิ่มคอลัมน์รูปภาพตัวอย่าง
- เพิ่มคอลัมน์ URL รูปภาพที่แก้ไขได้
- ตรวจ URL รูปเบื้องต้น
- ใช้ `<img onload/onerror>` ตรวจว่ารูปเปิดได้จาก browser หรือไม่
- ตรวจซ้ำด้วยลำดับความมั่นใจ: barcode → SKU → ชื่อ+ขนาด
- แสดงความแตกต่างของข้อมูลเดิมกับข้อมูลใหม่
- ให้เลือกต่อแถว: แก้ไข / เพิ่มเป็นตัวใหม่ / ข้าม
- เพิ่มปุ่มเลือกทั้งชุด
- ถ้าไฟล์ไม่มี URL รูป ระบบจะคงรูปเดิมของสินค้าที่มีอยู่ ไม่ลบรูปโดยไม่ตั้งใจ
- ไม่ถือว่าสินค้าที่ตรงกันเป็น error โดยอัตโนมัติอีกต่อไป แต่ให้ผู้ใช้ตัดสินใจ

## แนวทางความปลอดภัย
- ก่อน commit ยังผ่าน Manager PIN + Confirm เดิม
- แถวที่ validation error ไม่ถูกนำเข้า
- แถวที่เลือก SKIP ไม่ถูกแตะ
- เก็บ index.original.html สำหรับ rollback

## V7.02 — Production Import Bridge
- แยกโค้ดส่วน Import Safety ที่เพิ่มใหม่เป็นไฟล์ JS โดยไม่รื้อ inline runtime เดิม
- เพิ่ม local recovery plan ของ Import Preview
- เพิ่มตรวจรูปแบบมี timeout และสถานะ OK / BAD / BLOCKED / EMPTY
- เพิ่ม duplicate index แบบ barcode → SKU → ชื่อ+ขนาด → fuzzy
- เพิ่ม API สำหรับ field-level decision (APPLY / SKIP)
- เพิ่ม optional Supabase Import Center persistence เมื่อผู้ใช้ authenticated
- PWA cache version อัปเดตเป็น V7.02
