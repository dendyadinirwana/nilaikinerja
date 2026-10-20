import React, { useState } from 'react';
import { invoke } from '@tauri-apps/api/core';
import {
  FileText,
  FileSpreadsheet,
  Presentation,
  Image as ImageIcon,
  Calendar,
  Clock,
  Download,
  Trash2,
  FolderOpen,
} from 'lucide-react';
import { ActivityRecord } from '../types';
import { exportDailyDocx } from '../utils/docxExport';

interface HistoryScreenProps {
  activities: ActivityRecord[];
  onDeleteActivity: (id: string) => void;
}

export const HistoryScreen: React.FC<HistoryScreenProps> = ({
  activities,
  onDeleteActivity,
}) => {
  const [filterDate, setFilterDate] = useState<'today' | 'all'>('today');
  const todayStr = new Date().toISOString().split('T')[0];

  const filtered = filterDate === 'today'
    ? activities.filter((a) => a.date === todayStr)
    : activities;

  const handleReveal = async (path: string) => {
    try {
      await invoke('reveal_in_explorer', { path });
    } catch (e) {
      console.warn('Could not reveal in explorer:', e);
    }
  };

  const getFormatIcon = (kind: string) => {
    switch (kind) {
      case 'presentation':
        return <Presentation className="w-4 h-4 text-amber-400" />;
      case 'spreadsheet':
        return <FileSpreadsheet className="w-4 h-4 text-emerald-400" />;
      case 'image':
        return <ImageIcon className="w-4 h-4 text-purple-400" />;
      default:
        return <FileText className="w-4 h-4 text-blue-400" />;
    }
  };

  return (
    <div className="flex flex-col h-full p-5 space-y-4 overflow-y-auto">
      {/* Top Header */}
      <div className="flex items-center justify-between pb-3 border-b border-white/10 shrink-0">
        <div>
          <h2 className="text-sm font-semibold text-white">Riwayat Capaian Kinerja</h2>
          <p className="text-xs text-white/50">
            Daftar kegiatan terekam beserta lampiran dokumen pendukung.
          </p>
        </div>

        <div className="flex items-center gap-2">
          {/* Filter toggle */}
          <div className="flex bg-white/5 border border-white/10 rounded-lg p-0.5 text-xs">
            <button
              onClick={() => setFilterDate('today')}
              className={`px-3 py-1 rounded-md transition-colors ${
                filterDate === 'today'
                  ? 'bg-blue-600 text-white font-medium'
                  : 'text-white/60 hover:text-white'
              }`}
            >
              Hari Ini
            </button>
            <button
              onClick={() => setFilterDate('all')}
              className={`px-3 py-1 rounded-md transition-colors ${
                filterDate === 'all'
                  ? 'bg-blue-600 text-white font-medium'
                  : 'text-white/60 hover:text-white'
              }`}
            >
              Semua ({activities.length})
            </button>
          </div>

          <button
            onClick={() => exportDailyDocx(todayStr, filtered)}
            disabled={filtered.length === 0}
            className="h-[32px] px-3 bg-white/5 hover:bg-white/10 border border-white/10 rounded-lg text-xs font-medium text-white flex items-center gap-1.5 transition-colors disabled:opacity-40"
          >
            <Download className="w-3.5 h-3.5 text-emerald-400" />
            Ekspor .docx
          </button>
        </div>
      </div>

      {/* List */}
      {filtered.length === 0 ? (
        <div className="flex-1 flex flex-col items-center justify-center p-8 text-center text-xs text-white/40 border border-white/5 rounded-2xl bg-white/[0.01]">
          <Calendar className="w-8 h-8 text-white/20 mb-2" />
          <span>Tidak ada catatan kinerja pada rentang ini.</span>
        </div>
      ) : (
        <div className="space-y-2.5">
          {filtered.map((act) => (
            <div
              key={act.id}
              className="p-3.5 bg-white/5 border border-white/10 rounded-xl text-xs space-y-2 hover:border-white/20 transition-colors"
            >
              <div className="flex items-start justify-between gap-2">
                <div className="space-y-0.5">
                  <div className="text-sm font-semibold text-white">{act.title}</div>
                  <div className="flex items-center gap-2 text-white/50 text-[11px]">
                    <span className="font-mono text-blue-300">
                      {act.startTime} - {act.endTime}
                    </span>
                    <span>•</span>
                    <span className="flex items-center gap-1">
                      <Clock className="w-3 h-3 text-emerald-400" />
                      {act.durationMinutes} menit
                    </span>
                    <span>•</span>
                    <span>{act.date}</span>
                  </div>
                </div>

                <button
                  onClick={() => onDeleteActivity(act.id)}
                  className="p-1 hover:bg-rose-500/20 text-white/40 hover:text-rose-400 rounded transition-colors"
                  title="Hapus Catatan"
                >
                  <Trash2 className="w-3.5 h-3.5" />
                </button>
              </div>

              {act.detail && (
                <div className="bg-black/20 p-2.5 rounded-lg text-white/80 whitespace-pre-wrap leading-relaxed border border-white/5">
                  {act.detail}
                </div>
              )}

              {act.attachments && act.attachments.length > 0 && (
                <div className="pt-1 space-y-1">
                  <div className="text-[10px] uppercase tracking-wider font-semibold text-white/40">
                    Dokumen Bukti ({act.attachments.length})
                  </div>
                  <div className="grid grid-cols-2 gap-2">
                    {act.attachments.map((att) => (
                      <div
                        key={att.id}
                        className="flex items-center justify-between p-2 bg-white/[0.03] border border-white/5 rounded-lg text-white/80 text-[11px]"
                      >
                        <div className="flex items-center gap-2 truncate">
                          {getFormatIcon(att.kind)}
                          <span className="truncate">{att.name}</span>
                        </div>
                        <button
                          onClick={() => handleReveal(att.path)}
                          className="p-1 hover:bg-white/10 rounded text-white/50 hover:text-white shrink-0"
                          title="Buka di Explorer"
                        >
                          <FolderOpen className="w-3 h-3" />
                        </button>
                      </div>
                    ))}
                  </div>
                </div>
              )}
            </div>
          ))}
        </div>
      )}
    </div>
  );
};
