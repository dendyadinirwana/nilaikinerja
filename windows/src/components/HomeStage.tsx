import React from 'react';
import {
  Plus,
  Sparkles,
  Download,
  Clock,
  CheckCircle2,
  FileText,
  Calendar,
  ChevronRight,
} from 'lucide-react';
import { RobotHead } from './RobotHead';
import { ActivityRecord, RobotState } from '../types';
import { exportDailyDocx } from '../utils/docxExport';

interface HomeStageProps {
  robotState: RobotState;
  setRobotState: (s: RobotState) => void;
  activities: ActivityRecord[];
  onNavigateAdd: () => void;
  onNavigateAI: () => void;
  onNavigateHistory: () => void;
}

export const HomeStage: React.FC<HomeStageProps> = ({
  robotState,
  setRobotState,
  activities,
  onNavigateAdd,
  onNavigateAI,
  onNavigateHistory,
}) => {
  const todayStr = new Date().toISOString().split('T')[0];
  const todayActivities = activities.filter((a) => a.date === todayStr);

  const totalMinutes = todayActivities.reduce((acc, curr) => acc + (curr.durationMinutes || 60), 0);
  const totalHours = (totalMinutes / 60).toFixed(1);

  const handleExport = () => {
    exportDailyDocx(todayStr, todayActivities.length > 0 ? todayActivities : activities);
  };

  return (
    <div className="flex flex-col h-full overflow-y-auto p-5 space-y-5">
      {/* 3D Robot Head Stage */}
      <div className="relative flex flex-col items-center justify-center p-4 bg-gradient-to-b from-blue-950/20 via-white/[0.02] to-transparent rounded-2xl border border-white/5">
        <RobotHead
          state={robotState}
          size={140}
          onClick={() => {
            setRobotState('happy');
            setTimeout(() => setRobotState('idle'), 2500);
          }}
        />

        <div className="mt-2 flex items-center gap-2">
          <span className="w-2 h-2 rounded-full bg-emerald-400 animate-pulse" />
          <span className="text-xs font-medium text-white/70 capitalize">
            Robot State: {robotState}
          </span>
        </div>
        <p className="text-[11px] text-white/40 mt-0.5">
          Klik robot untuk berinteraksi lompat & putar!
        </p>
      </div>

      {/* Metrics Row */}
      <div className="grid grid-cols-3 gap-3">
        <div className="bg-white/5 border border-white/10 rounded-xl p-3 flex flex-col justify-between">
          <div className="flex items-center justify-between text-white/50 text-xs">
            <span>Kegiatan Hari Ini</span>
            <CheckCircle2 className="w-3.5 h-3.5 text-blue-400" />
          </div>
          <div className="text-xl font-bold text-white mt-1">
            {todayActivities.length} <span className="text-xs font-normal text-white/50">item</span>
          </div>
        </div>

        <div className="bg-white/5 border border-white/10 rounded-xl p-3 flex flex-col justify-between">
          <div className="flex items-center justify-between text-white/50 text-xs">
            <span>Waktu Kinerja</span>
            <Clock className="w-3.5 h-3.5 text-emerald-400" />
          </div>
          <div className="text-xl font-bold text-white mt-1">
            {totalHours} <span className="text-xs font-normal text-white/50">jam</span>
          </div>
        </div>

        <div className="bg-white/5 border border-white/10 rounded-xl p-3 flex flex-col justify-between">
          <div className="flex items-center justify-between text-white/50 text-xs">
            <span>Target Harian</span>
            <Calendar className="w-3.5 h-3.5 text-amber-400" />
          </div>
          <div className="text-xl font-bold text-white mt-1">
            7.5 <span className="text-xs font-normal text-white/50">jam</span>
          </div>
        </div>
      </div>

      {/* Action Buttons - Standard 36pt */}
      <div className="grid grid-cols-3 gap-2.5">
        <button
          onClick={onNavigateAdd}
          className="h-[36px] bg-blue-600 hover:bg-blue-500 rounded-lg text-xs font-medium text-white flex items-center justify-center gap-1.5 transition-colors shadow-lg shadow-blue-500/20"
        >
          <Plus className="w-4 h-4" />
          Catat Baru
        </button>

        <button
          onClick={onNavigateAI}
          className="h-[36px] bg-white/5 hover:bg-white/10 border border-white/10 rounded-lg text-xs font-medium text-white/80 hover:text-white flex items-center justify-center gap-1.5 transition-colors"
        >
          <Sparkles className="w-4 h-4 text-purple-400" />
          Tanya AI
        </button>

        <button
          onClick={handleExport}
          className="h-[36px] bg-white/5 hover:bg-white/10 border border-white/10 rounded-lg text-xs font-medium text-white/80 hover:text-white flex items-center justify-center gap-1.5 transition-colors"
          title="Unduh laporan kinerja berformat Microsoft Word .docx"
        >
          <Download className="w-4 h-4 text-emerald-400" />
          Unduh .docx
        </button>
      </div>

      {/* Today's Activity Log */}
      <div className="space-y-2 pt-1">
        <div className="flex items-center justify-between">
          <span className="text-xs font-semibold text-white/80">Riwayat Kegiatan Hari Ini</span>
          <button
            onClick={onNavigateHistory}
            className="text-[11px] text-blue-400 hover:text-blue-300 flex items-center gap-0.5"
          >
            Lihat Semua <ChevronRight className="w-3 h-3" />
          </button>
        </div>

        {todayActivities.length === 0 ? (
          <div className="bg-white/[0.02] border border-white/5 rounded-xl p-6 text-center text-xs text-white/40">
            Belum ada kegiatan yang dicatat hari ini. Tarik dokumen kerja ke notch atau klik tombol "Catat Baru"!
          </div>
        ) : (
          <div className="space-y-1.5">
            {todayActivities.map((act) => (
              <div
                key={act.id}
                className="flex items-center justify-between p-3 bg-white/5 border border-white/10 rounded-xl text-xs text-white hover:bg-white/[0.08] transition-colors"
              >
                <div className="space-y-0.5 truncate pr-2">
                  <div className="font-medium truncate">{act.title}</div>
                  <div className="text-[11px] text-white/40 flex items-center gap-2">
                    <span className="font-mono">{act.startTime} - {act.endTime}</span>
                    <span>•</span>
                    <span>{act.durationMinutes} menit</span>
                    {act.attachments.length > 0 && (
                      <>
                        <span>•</span>
                        <span className="text-blue-400 flex items-center gap-1">
                          <FileText className="w-3 h-3" />
                          {act.attachments.length} berkas
                        </span>
                      </>
                    )}
                  </div>
                </div>

                <div className="shrink-0">
                  <span className="px-2 py-0.5 bg-blue-500/15 text-blue-300 rounded text-[10px] font-medium border border-blue-500/30">
                    Terekam
                  </span>
                </div>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
};
