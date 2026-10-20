import React from 'react';
import {
  Home,
  PlusCircle,
  History,
  Bot,
  Settings,
  Minimize2,
  Sparkles,
} from 'lucide-react';
import { ScreenTab, WindowMode } from '../types';

interface TopIslandProps {
  windowMode: WindowMode;
  setWindowMode: (m: WindowMode) => void;
  activeTab: ScreenTab;
  setActiveTab: (t: ScreenTab) => void;
  todayCount: number;
  glowIntensity: number;
}

export const TopIsland: React.FC<TopIslandProps> = ({
  windowMode,
  setWindowMode,
  activeTab,
  setActiveTab,
  todayCount,
  glowIntensity,
}) => {
  // If in idle mode, render minimal top-center capsule
  if (windowMode === 'idle') {
    return (
      <div
        onClick={() => setWindowMode('expanded')}
        className="w-[300px] h-[40px] mx-auto bg-[#0B0E14] text-white rounded-full flex items-center justify-between px-3.5 cursor-pointer select-none transition-all duration-300 hover:scale-102 shadow-2xl"
        style={{
          border: `1.5px solid rgba(96, 165, 250, ${glowIntensity})`,
          boxShadow: `0 0 16px rgba(96, 165, 250, ${glowIntensity * 0.4})`,
        }}
        title="Klik untuk membuka NilaiKinerja Floating Island"
      >
        <div className="flex items-center gap-2">
          <div className="w-2 h-2 rounded-full bg-blue-400 animate-pulse" />
          <span className="text-xs font-semibold tracking-wide">NilaiKinerja</span>
        </div>

        <div className="flex items-center gap-2 text-[11px] text-white/60">
          <span className="px-2 py-0.5 rounded-full bg-white/10 text-white/80 font-mono">
            {todayCount} Kegiatan
          </span>
          <Sparkles className="w-3.5 h-3.5 text-blue-400" />
        </div>
      </div>
    );
  }

  // Expanded mode header navigation
  return (
    <div className="flex items-center justify-between px-4 py-3 border-b border-white/10 bg-[#0B0E14] select-none">
      {/* Brand title */}
      <div className="flex items-center gap-2">
        <div className="w-2.5 h-2.5 rounded-full bg-blue-500 shadow-[0_0_8px_#3B82F6]" />
        <span className="text-xs font-bold text-white tracking-wider uppercase">NilaiKinerja</span>
      </div>

      {/* Solid pill tabs - Standardized 36pt height */}
      <div className="flex bg-[#1E222A] rounded-xl p-1 text-xs gap-1">
        <button
          onClick={() => setActiveTab('home')}
          className={`h-[28px] px-3 rounded-lg flex items-center gap-1.5 transition-colors ${
            activeTab === 'home'
              ? 'bg-blue-600 text-white font-medium'
              : 'text-white/60 hover:text-white'
          }`}
        >
          <Home className="w-3.5 h-3.5" />
          Beranda
        </button>

        <button
          onClick={() => setActiveTab('add')}
          className={`h-[28px] px-3 rounded-lg flex items-center gap-1.5 transition-colors ${
            activeTab === 'add'
              ? 'bg-blue-600 text-white font-medium'
              : 'text-white/60 hover:text-white'
          }`}
        >
          <PlusCircle className="w-3.5 h-3.5" />
          Catat
        </button>

        <button
          onClick={() => setActiveTab('history')}
          className={`h-[28px] px-3 rounded-lg flex items-center gap-1.5 transition-colors ${
            activeTab === 'history'
              ? 'bg-blue-600 text-white font-medium'
              : 'text-white/60 hover:text-white'
          }`}
        >
          <History className="w-3.5 h-3.5" />
          Riwayat
        </button>

        <button
          onClick={() => setActiveTab('ai')}
          className={`h-[28px] px-3 rounded-lg flex items-center gap-1.5 transition-colors ${
            activeTab === 'ai'
              ? 'bg-purple-600 text-white font-medium'
              : 'text-white/60 hover:text-white'
          }`}
        >
          <Bot className="w-3.5 h-3.5" />
          Tanya AI
        </button>

        <button
          onClick={() => setActiveTab('settings')}
          className={`h-[28px] px-3 rounded-lg flex items-center gap-1.5 transition-colors ${
            activeTab === 'settings'
              ? 'bg-blue-600 text-white font-medium'
              : 'text-white/60 hover:text-white'
          }`}
        >
          <Settings className="w-3.5 h-3.5" />
          Pengaturan
        </button>
      </div>

      {/* Minimize / Collapse */}
      <button
        onClick={() => setWindowMode('idle')}
        className="p-1.5 hover:bg-white/10 rounded-lg text-white/50 hover:text-white transition-colors"
        title="Sembunyikan ke Island (Idle)"
      >
        <Minimize2 className="w-4 h-4" />
      </button>
    </div>
  );
};
