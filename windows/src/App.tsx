import React, { useState, useEffect } from 'react';
import { invoke } from '@tauri-apps/api/core';
import confetti from 'canvas-confetti';
import { TopIsland } from './components/TopIsland';
import { HomeStage } from './components/HomeStage';
import { ActivityForm } from './components/ActivityForm';
import { HistoryScreen } from './components/HistoryScreen';
import { AIChatScreen } from './components/AIChatScreen';
import { SettingsScreen } from './components/SettingsScreen';
import { ActivityRecord, AppSettings, RobotState, ScreenTab, WindowMode } from './types';
import { DEFAULT_SETTINGS, loadData, saveData } from './utils/storage';
import './App.css';

export const App: React.FC = () => {
  const [windowMode, setWindowModeState] = useState<WindowMode>('expanded');
  const [activeTab, setActiveTab] = useState<ScreenTab>('home');
  const [robotState, setRobotState] = useState<RobotState>('idle');
  const [activities, setActivities] = useState<ActivityRecord[]>([]);
  const [settings, setSettings] = useState<AppSettings>(DEFAULT_SETTINGS);

  // Load persisted records and settings on mount
  useEffect(() => {
    loadData().then((data) => {
      setActivities(data.activities);
      setSettings(data.settings);
    });
  }, []);

  // Sync window size with Rust backend
  const setWindowMode = async (mode: WindowMode) => {
    setWindowModeState(mode);
    try {
      await invoke('set_window_mode', { mode });
    } catch (e) {
      console.warn('Could not set window mode in Rust:', e);
    }
  };

  // Determine sleeping state based on work hours
  useEffect(() => {
    const checkWorkHours = () => {
      const now = new Date();
      const currentMinutes = now.getHours() * 60 + now.getMinutes();
      const startMinutes = settings.workStartHour * 60 + settings.workStartMinute;
      const endMinutes = settings.workEndHour * 60 + settings.workEndMinute;

      if (currentMinutes < startMinutes || currentMinutes > endMinutes) {
        if (robotState === 'idle') {
          setRobotState('sleeping');
        }
      } else if (robotState === 'sleeping') {
        setRobotState('idle');
      }
    };

    checkWorkHours();
    const interval = setInterval(checkWorkHours, 60000);
    return () => clearInterval(interval);
  }, [settings, robotState]);

  // Handle Save
  const handleSaveActivity = (record: ActivityRecord) => {
    const updated = [record, ...activities];
    setActivities(updated);
    saveData({ activities: updated, settings });

    // Blast celebratory confetti!
    try {
      confetti({
        particleCount: 80,
        spread: 70,
        origin: { y: 0.15 },
        colors: ['#60A5FA', '#3B82F6', '#10B981', '#F59E0B', '#EC4899'],
      });
    } catch {}

    // Transition back to home with celebratory robot
    setActiveTab('home');
    setRobotState('happy');
    setTimeout(() => {
      setRobotState('idle');
    }, 3200);
  };

  // Handle Delete
  const handleDeleteActivity = (id: string) => {
    const updated = activities.filter((a) => a.id !== id);
    setActivities(updated);
    saveData({ activities: updated, settings });
  };

  // Handle Settings Update
  const handleUpdateSettings = (newSettings: AppSettings) => {
    setSettings(newSettings);
    saveData({ activities, settings: newSettings });
  };

  const todayStr = new Date().toISOString().split('T')[0];
  const todayCount = activities.filter((a) => a.date === todayStr).length;

  return (
    <div className="w-full h-full flex flex-col items-center justify-start overflow-hidden bg-transparent pt-1">
      {/* Dynamic Island Window Header / Idle Capsule */}
      <div className="w-full shrink-0 flex justify-center">
        <TopIsland
          windowMode={windowMode}
          setWindowMode={setWindowMode}
          activeTab={activeTab}
          setActiveTab={setActiveTab}
          todayCount={todayCount}
          glowIntensity={settings.idleGlowIntensity}
        />
      </div>

      {/* Expanded Main Card Container */}
      {windowMode === 'expanded' && (
        <div
          className="w-[660px] h-[580px] mt-2 bg-[#0B0E14] text-white rounded-2xl flex flex-col overflow-hidden shadow-2xl relative transition-all duration-300"
          style={{
            border: `1.5px solid rgba(96, 165, 250, ${settings.idleGlowIntensity * 0.7})`,
            boxShadow: `0 20px 50px rgba(0, 0, 0, 0.8), 0 0 24px rgba(96, 165, 250, ${
              settings.idleGlowIntensity * 0.25
            })`,
          }}
        >
          {/* Main View Router */}
          <div className="flex-1 overflow-hidden">
            {activeTab === 'home' && (
              <HomeStage
                robotState={robotState}
                setRobotState={setRobotState}
                activities={activities}
                onNavigateAdd={() => setActiveTab('add')}
                onNavigateAI={() => setActiveTab('ai')}
                onNavigateHistory={() => setActiveTab('history')}
              />
            )}

            {activeTab === 'add' && (
              <ActivityForm
                onSave={handleSaveActivity}
                onCancel={() => setActiveTab('home')}
                setRobotState={setRobotState}
              />
            )}

            {activeTab === 'history' && (
              <HistoryScreen
                activities={activities}
                onDeleteActivity={handleDeleteActivity}
              />
            )}

            {activeTab === 'ai' && (
              <AIChatScreen
                settings={settings}
                setRobotState={setRobotState}
                onLogAsActivity={(_text) => {
                  setActiveTab('add');
                }}
              />
            )}

            {activeTab === 'settings' && (
              <SettingsScreen
                settings={settings}
                onUpdateSettings={handleUpdateSettings}
              />
            )}
          </div>
        </div>
      )}
    </div>
  );
};

export default App;
