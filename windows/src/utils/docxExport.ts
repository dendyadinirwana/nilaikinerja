import JSZip from 'jszip';
import { ActivityRecord } from '../types';

function escapeXml(unsafe: string): string {
  return unsafe
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&apos;');
}

export async function exportDailyDocx(dateStr: string, activities: ActivityRecord[]): Promise<void> {
  const zip = new JSZip();

  // 1. [Content_Types].xml
  zip.file(
    '[Content_Types].xml',
    `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
</Types>`
  );

  // 2. _rels/.rels
  zip.file(
    '_rels/.rels',
    `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>`
  );

  // 3. word/document.xml
  let tableRowsXml = `
    <w:tr>
      <w:tc><w:tcPr><w:tcW w:w="800" w:type="dxa"/><w:shd w:val="clear" w:color="auto" w:fill="F1F5F9"/></w:tcPr><w:p><w:pPr><w:jc w:val="center"/></w:pPr><w:r><w:rPr><w:b/><w:sz w:val="20"/></w:rPr><w:t>No</w:t></w:r></w:p></w:tc>
      <w:tc><w:tcPr><w:tcW w:w="1800" w:type="dxa"/><w:shd w:val="clear" w:color="auto" w:fill="F1F5F9"/></w:tcPr><w:p><w:pPr><w:jc w:val="center"/></w:pPr><w:r><w:rPr><w:b/><w:sz w:val="20"/></w:rPr><w:t>Waktu</w:t></w:r></w:p></w:tc>
      <w:tc><w:tcPr><w:tcW w:w="3000" w:type="dxa"/><w:shd w:val="clear" w:color="auto" w:fill="F1F5F9"/></w:tcPr><w:p><w:r><w:rPr><w:b/><w:sz w:val="20"/></w:rPr><w:t>Kegiatan</w:t></w:r></w:p></w:tc>
      <w:tc><w:tcPr><w:tcW w:w="3000" w:type="dxa"/><w:shd w:val="clear" w:color="auto" w:fill="F1F5F9"/></w:tcPr><w:p><w:r><w:rPr><w:b/><w:sz w:val="20"/></w:rPr><w:t>Hasil / Detail</w:t></w:r></w:p></w:tc>
      <w:tc><w:tcPr><w:tcW w:w="2000" w:type="dxa"/><w:shd w:val="clear" w:color="auto" w:fill="F1F5F9"/></w:tcPr><w:p><w:r><w:rPr><w:b/><w:sz w:val="20"/></w:rPr><w:t>Dokumen Pendukung</w:t></w:r></w:p></w:tc>
    </w:tr>
  `;

  let totalMinutes = 0;
  activities.forEach((act, idx) => {
    totalMinutes += act.durationMinutes || 60;
    const docs = act.attachments.map((a) => a.name).join(', ') || '-';
    tableRowsXml += `
      <w:tr>
        <w:tc><w:tcPr><w:tcW w:w="800" w:type="dxa"/></w:tcPr><w:p><w:pPr><w:jc w:val="center"/></w:pPr><w:r><w:rPr><w:sz w:val="19"/></w:rPr><w:t>${idx + 1}</w:t></w:r></w:p></w:tc>
        <w:tc><w:tcPr><w:tcW w:w="1800" w:type="dxa"/></w:tcPr><w:p><w:pPr><w:jc w:val="center"/></w:pPr><w:r><w:rPr><w:sz w:val="19"/></w:rPr><w:t>${escapeXml(act.startTime)} - ${escapeXml(act.endTime)}</w:t></w:r></w:p></w:tc>
        <w:tc><w:tcPr><w:tcW w:w="3000" w:type="dxa"/></w:tcPr><w:p><w:r><w:rPr><w:b/><w:sz w:val="19"/></w:rPr><w:t>${escapeXml(act.title)}</w:t></w:r></w:p></w:tc>
        <w:tc><w:tcPr><w:tcW w:w="3000" w:type="dxa"/></w:tcPr><w:p><w:r><w:rPr><w:sz w:val="19"/></w:rPr><w:t>${escapeXml(act.detail || '-')}</w:t></w:r></w:p></w:tc>
        <w:tc><w:tcPr><w:tcW w:w="2000" w:type="dxa"/></w:tcPr><w:p><w:r><w:rPr><w:sz w:val="19"/></w:rPr><w:t>${escapeXml(docs)}</w:t></w:r></w:p></w:tc>
      </w:tr>
    `;
  });

  const hours = Math.floor(totalMinutes / 60);
  const mins = totalMinutes % 60;

  const docXml = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>
    <w:p>
      <w:pPr><w:jc w:val="center"/><w:spacing w:after="160"/></w:pPr>
      <w:r><w:rPr><w:b/><w:sz w:val="32"/><w:color w:val="0F172A"/></w:rPr><w:t>LAPORAN CAPAIAN KINERJA HARIAN</w:t></w:r>
    </w:p>
    <w:p>
      <w:pPr><w:jc w:val="center"/><w:spacing w:after="320"/></w:pPr>
      <w:r><w:rPr><w:sz w:val="22"/><w:color w:val="475569"/></w:rPr><w:t>Tanggal: ${escapeXml(dateStr)}  |  Total Waktu Kinerja: ${hours} Jam ${mins} Menit</w:t></w:r>
    </w:p>
    <w:tbl>
      <w:tblPr>
        <w:tblW w:w="10600" w:type="dxa"/>
        <w:tblBorders>
          <w:top w:val="single" w:sz="6" w:space="0" w:color="CBD5E1"/>
          <w:bottom w:val="single" w:sz="6" w:space="0" w:color="CBD5E1"/>
          <w:left w:val="single" w:sz="6" w:space="0" w:color="CBD5E1"/>
          <w:right w:val="single" w:sz="6" w:space="0" w:color="CBD5E1"/>
          <w:insideH w:val="single" w:sz="4" w:space="0" w:color="E2E8F0"/>
          <w:insideV w:val="single" w:sz="4" w:space="0" w:color="E2E8F0"/>
        </w:tblBorders>
      </w:tblPr>
      ${tableRowsXml}
    </w:tbl>
    <w:p><w:pPr><w:spacing w:before="400"/></w:pPr><w:r><w:rPr><w:i/><w:sz w:val="18"/><w:color w:val="64748B"/></w:rPr><w:t>Dokumen ini diekspor secara otomatis melalui NilaiKinerja.</w:t></w:r></w:p>
  </w:body>
</w:document>`;

  zip.file('word/document.xml', docXml);

  const blob = await zip.generateAsync({ type: 'blob' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = `Laporan_Kinerja_${dateStr}.docx`;
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  URL.revokeObjectURL(url);
}
