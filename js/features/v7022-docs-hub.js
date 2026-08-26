/* SmartPOS V7.02.2 - Unified "เอกสารและธุรกรรม" summary + export hub
 *
 * Additive only: mounts a 3rd tab ("📊 สรุป & Export") inside the existing
 * #view-documents page, next to the existing SYSTEM/EXTERNAL tabs, and wraps
 * window.switchDocTab so the existing two tabs keep working exactly as before.
 *
 * Pulls from data that already exists — no new schema, no new Supabase table:
 *   - db.bills        (sales)
 *   - db.cashLedger    (income/expense book, already used for the tax report)
 *   - db.documents     (external uploaded docs: supplier invoices, utility bills, ...)
 *   - SmartPOSV702Import.getLocalPlan() (most recent stock-import batch, if any)
 *
 * Gives a shop owner / accountant one screen to pick a date range, see totals
 * per category, and export CSV files (opens correctly in Excel with Thai text)
 * to hand off for bookkeeping — without hunting through separate tabs.
 */
(() => {
  'use strict';

  function todayStr() {
    return new Date().toISOString().slice(0, 10);
  }
  function firstOfMonthStr() {
    const d = new Date();
    return new Date(d.getFullYear(), d.getMonth(), 1).toISOString().slice(0, 10);
  }
  function inRange(ts, fromStr, toStr) {
    const t = new Date(ts).getTime();
    const from = new Date(fromStr + 'T00:00:00').getTime();
    const to = new Date(toStr + 'T23:59:59').getTime();
    return t >= from && t <= to;
  }
  function money(n) {
    return Number(n || 0).toLocaleString('th-TH', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
  }
  function csvEscape(v) {
    const s = String(v ?? '');
    return /[",\n]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s;
  }
  function downloadCSV(filename, rows) {
    // \uFEFF (UTF-8 BOM) so Excel on Windows opens Thai text correctly instead of mojibake.
    const csv = '\uFEFF' + rows.map(r => r.map(csvEscape).join(',')).join('\r\n');
    const blob = new Blob([csv], { type: 'text/csv;charset=utf-8;' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url; a.download = filename;
    document.body.appendChild(a); a.click(); a.remove();
    setTimeout(() => URL.revokeObjectURL(url), 2000);
  }

  function getRange() {
    const from = document.getElementById('dh-date-from')?.value || firstOfMonthStr();
    const to = document.getElementById('dh-date-to')?.value || todayStr();
    return { from, to };
  }

  function computeSummary() {
    const { from, to } = getRange();
    const db = window.db || {};

    const bills = (db.bills || []).filter(b => inRange(b.time, from, to));
    const salesTotal = bills.reduce((s, b) => s + (b.isRefunded ? 0 : Number(b.total || 0) - Number(b.refundAmount || 0)), 0);
    const salesCount = bills.length;

    const ledger = (db.cashLedger || []).filter(tx => inRange(tx.date, from, to));
    const incomeTotal = ledger.reduce((s, tx) => s + Number(tx.income || 0), 0);
    const expenseTotal = ledger.reduce((s, tx) => s + Number(tx.expense || 0), 0);
    const byType = {};
    ledger.forEach(tx => {
      const k = tx.type || 'other';
      byType[k] = byType[k] || { income: 0, expense: 0, count: 0 };
      byType[k].income += Number(tx.income || 0);
      byType[k].expense += Number(tx.expense || 0);
      byType[k].count += 1;
    });

    const docs = (db.documents || []).filter(d => inRange(d.time, from, to));
    const docsByCat = {};
    docs.forEach(d => { docsByCat[d.category] = (docsByCat[d.category] || 0) + 1; });

    let lastImport = null;
    try { lastImport = window.SmartPOSV702Import?.getLocalPlan?.() || null; } catch (e) { lastImport = null; }
    const importInRange = lastImport && inRange(lastImport.createdAt, from, to) ? lastImport : null;

    return { from, to, bills, salesTotal, salesCount, ledger, incomeTotal, expenseTotal, byType, docs, docsByCat, importInRange };
  }

  function renderSummary() {
    const s = computeSummary();
    const el = document.getElementById('dh-summary-body');
    if (!el) return;

    const byTypeRows = Object.entries(s.byType).sort((a, b) => b[1].income + b[1].expense - (a[1].income + a[1].expense))
      .map(([type, v]) => `
        <tr class="border-b last:border-0">
          <td class="p-2 text-[11px]">${window.escapeHTML ? window.escapeHTML(type) : type}</td>
          <td class="p-2 text-[11px] text-right">${v.count}</td>
          <td class="p-2 text-[11px] text-right text-emerald-600">${v.income ? money(v.income) : '-'}</td>
          <td class="p-2 text-[11px] text-right text-rose-500">${v.expense ? money(v.expense) : '-'}</td>
        </tr>`).join('') || `<tr><td colspan="4" class="p-4 text-center text-slate-400 text-xs">ไม่มีรายการในช่วงนี้</td></tr>`;

    const docCatRows = Object.entries(s.docsByCat).map(([cat, n]) => `
      <div class="flex justify-between text-[11px] py-1 border-b last:border-0">
        <span>${window.escapeHTML ? window.escapeHTML(cat) : cat}</span><span class="font-bold">${n}</span>
      </div>`).join('') || `<p class="text-center text-slate-400 text-xs py-3">ไม่มีเอกสารอัปโหลดในช่วงนี้</p>`;

    el.innerHTML = `
      <div class="grid grid-cols-2 sm:grid-cols-4 gap-2 mb-4">
        <div class="bg-indigo-50 border border-indigo-200 rounded-2xl p-3">
          <p class="text-[9px] font-bold text-indigo-400 uppercase">ยอดขาย</p>
          <p class="text-lg font-black text-indigo-700">฿${money(s.salesTotal)}</p>
          <p class="text-[9px] text-slate-400">${s.salesCount} บิล</p>
        </div>
        <div class="bg-emerald-50 border border-emerald-200 rounded-2xl p-3">
          <p class="text-[9px] font-bold text-emerald-500 uppercase">รายรับ (บัญชี)</p>
          <p class="text-lg font-black text-emerald-600">฿${money(s.incomeTotal)}</p>
        </div>
        <div class="bg-rose-50 border border-rose-200 rounded-2xl p-3">
          <p class="text-[9px] font-bold text-rose-400 uppercase">รายจ่าย (บัญชี)</p>
          <p class="text-lg font-black text-rose-600">฿${money(s.expenseTotal)}</p>
        </div>
        <div class="bg-slate-50 border rounded-2xl p-3">
          <p class="text-[9px] font-bold text-slate-400 uppercase">สุทธิ</p>
          <p class="text-lg font-black ${s.incomeTotal - s.expenseTotal >= 0 ? 'text-slate-800' : 'text-rose-600'}">฿${money(s.incomeTotal - s.expenseTotal)}</p>
        </div>
      </div>

      <div class="bg-white rounded-2xl border shadow-sm overflow-hidden mb-4">
        <div class="px-3 pt-3 pb-1"><h5 class="text-xs font-bold text-slate-500">สมุดบัญชีรับ-จ่าย แยกตามประเภท</h5></div>
        <table class="w-full">
          <thead><tr class="bg-slate-50 text-[10px] text-slate-400">
            <th class="p-2 text-left">ประเภท</th><th class="p-2 text-right">จำนวน</th>
            <th class="p-2 text-right">รายรับ</th><th class="p-2 text-right">รายจ่าย</th>
          </tr></thead>
          <tbody>${byTypeRows}</tbody>
        </table>
      </div>

      <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
        <div class="bg-white rounded-2xl border shadow-sm p-3">
          <h5 class="text-xs font-bold text-slate-500 mb-2">เอกสารภายนอกที่อัปโหลด (${s.docs.length} ไฟล์)</h5>
          ${docCatRows}
        </div>
        <div class="bg-white rounded-2xl border shadow-sm p-3">
          <h5 class="text-xs font-bold text-slate-500 mb-2">รอบนำเข้าสินค้าล่าสุดในช่วงนี้</h5>
          ${s.importInRange
            ? `<p class="text-[11px] text-slate-600 leading-relaxed">📦 ${window.escapeHTML ? window.escapeHTML(s.importInRange.fileName || 'ไม่ระบุชื่อไฟล์') : (s.importInRange.fileName || 'ไม่ระบุชื่อไฟล์')}<br>
               ใหม่ ${s.importInRange.summary.add} | แก้ไข ${s.importInRange.summary.update} | ข้าม ${s.importInRange.summary.skip} | ผิดพลาด ${s.importInRange.summary.errors}<br>
               <span class="text-[9px] text-slate-400">${new Date(s.importInRange.createdAt).toLocaleString('th-TH')}</span></p>`
            : `<p class="text-[11px] text-slate-400">ไม่มีรอบนำเข้าสินค้าที่บันทึกไว้ในช่วงวันที่นี้ (ระบบเก็บไว้เฉพาะรอบล่าสุดในเครื่องนี้)</p>`}
        </div>
      </div>
    `;
  }

  function exportAllCSV() {
    const s = computeSummary();

    downloadCSV(`ยอดขาย_${s.from}_ถึง_${s.to}.csv`, [
      ['เลขที่บิล', 'วันที่-เวลา', 'ยอดรวม', 'ยอดคืนเงิน', 'วิธีชำระ', 'สถานะ'],
      ...s.bills.map(b => [
        b.id, new Date(b.time).toLocaleString('th-TH'),
        b.total, b.refundAmount || 0, b.method, b.isRefunded ? 'คืนเงินแล้ว' : 'ปกติ'
      ])
    ]);

    downloadCSV(`สมุดบัญชีรับจ่าย_${s.from}_ถึง_${s.to}.csv`, [
      ['วันที่', 'รายการ', 'ประเภท', 'รายรับ', 'รายจ่าย', 'อ้างอิง'],
      ...s.ledger.map(tx => [tx.date, tx.description, tx.type, tx.income || 0, tx.expense || 0, tx.refId || ''])
    ]);

    downloadCSV(`เอกสารภายนอก_${s.from}_ถึง_${s.to}.csv`, [
      ['ชื่อเอกสาร', 'ประเภท', 'วันที่อัปโหลด', 'หมายเหตุ', 'ลิงก์ไฟล์'],
      ...s.docs.map(d => [d.title, d.category, new Date(d.time).toLocaleDateString('th-TH'), d.note || '', d.fileUrl])
    ]);

    downloadCSV(`สรุปรวม_${s.from}_ถึง_${s.to}.csv`, [
      ['หัวข้อ', 'มูลค่า'],
      ['ช่วงวันที่', `${s.from} ถึง ${s.to}`],
      ['ยอดขายรวม', s.salesTotal], ['จำนวนบิล', s.salesCount],
      ['รายรับ (บัญชี)', s.incomeTotal], ['รายจ่าย (บัญชี)', s.expenseTotal],
      ['สุทธิ', s.incomeTotal - s.expenseTotal],
      ['จำนวนเอกสารภายนอก', s.docs.length]
    ]);

    if (typeof window.showToast === 'function') window.showToast('Export CSV ครบทั้งชุดแล้ว (4 ไฟล์)');
  }

  function mount() {
    const host = document.getElementById('view-documents');
    if (!host || document.getElementById('doc-tab-SUMMARY')) return;

    const tabBar = document.getElementById('doc-tab-EXTERNAL')?.parentElement;
    if (tabBar) {
      const btn = document.createElement('button');
      btn.id = 'doc-tab-SUMMARY';
      btn.className = 'flex-1 py-2 px-3 bg-slate-100 text-slate-500 rounded-xl font-bold text-xs border btn-touch';
      btn.textContent = '📊 สรุป & Export';
      btn.onclick = () => window.switchDocTab('SUMMARY');
      tabBar.appendChild(btn);
    }

    const externalPanel = document.getElementById('doc-panel-EXTERNAL');
    if (externalPanel && externalPanel.parentElement) {
      const panel = document.createElement('div');
      panel.id = 'doc-panel-SUMMARY';
      panel.className = 'hidden space-y-4';
      panel.innerHTML = `
        <div class="bg-white p-4 rounded-2xl border shadow-sm flex flex-wrap items-end gap-2 text-xs">
          <div>
            <label class="font-bold text-slate-500 block mb-1">จากวันที่</label>
            <input type="date" id="dh-date-from" value="${firstOfMonthStr()}" class="bg-slate-50 border p-2.5 rounded-xl outline-none text-slate-800">
          </div>
          <div>
            <label class="font-bold text-slate-500 block mb-1">ถึงวันที่</label>
            <input type="date" id="dh-date-to" value="${todayStr()}" class="bg-slate-50 border p-2.5 rounded-xl outline-none text-slate-800">
          </div>
          <button id="dh-btn-calc" class="py-2.5 px-4 bg-indigo-600 text-white rounded-xl font-bold btn-touch">คำนวณสรุป</button>
          <button id="dh-btn-export" class="py-2.5 px-4 bg-emerald-600 text-white rounded-xl font-bold btn-touch">📥 Export CSV ทั้งหมด</button>
        </div>
        <div id="dh-summary-body"></div>
      `;
      externalPanel.parentElement.appendChild(panel);
      document.getElementById('dh-btn-calc').onclick = renderSummary;
      document.getElementById('dh-btn-export').onclick = exportAllCSV;
    }

    const oldSwitch = window.switchDocTab;
    if (typeof oldSwitch === 'function' && !oldSwitch.__v7022wrapped) {
      const wrapped = function (tab) {
        if (tab === 'SUMMARY') {
          document.getElementById('doc-tab-SYSTEM').className = 'flex-1 py-2 px-3 bg-slate-100 text-slate-500 rounded-xl font-bold text-xs border btn-touch';
          document.getElementById('doc-tab-EXTERNAL').className = 'flex-1 py-2 px-3 bg-slate-100 text-slate-500 rounded-xl font-bold text-xs border btn-touch';
          document.getElementById('doc-tab-SUMMARY').className = 'flex-1 py-2 px-3 bg-indigo-600 text-white rounded-xl font-bold text-xs shadow-xs btn-touch';
          document.getElementById('doc-panel-SYSTEM').classList.add('hidden');
          document.getElementById('doc-panel-EXTERNAL').classList.add('hidden');
          document.getElementById('doc-panel-SUMMARY').classList.remove('hidden');
          renderSummary();
          return;
        }
        document.getElementById('doc-tab-SUMMARY').className = 'flex-1 py-2 px-3 bg-slate-100 text-slate-500 rounded-xl font-bold text-xs border btn-touch';
        document.getElementById('doc-panel-SUMMARY').classList.add('hidden');
        return oldSwitch(tab);
      };
      wrapped.__v7022wrapped = true;
      window.switchDocTab = wrapped;
    }
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', mount);
  else mount();

  window.SmartPOSV7022DocsHub = { computeSummary, exportAllCSV, renderSummary };
})();
