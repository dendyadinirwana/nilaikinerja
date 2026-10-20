import { invoke } from '@tauri-apps/api/core';
import { ActivityRecord, AppSettings } from '../types';

export const DEFAULT_SETTINGS: AppSettings = {
  workStartHour: 7,
  workStartMinute: 30,
  workEndHour: 17,
  workEndMinute: 0,
  reminderIntervalMinutes: 60,
  reminderEnabled: true,
  aiBaseURL: 'http://localhost:11434/v1',
  aiModel: 'llama3',
  aiApiKey: '',
  idleGlowIntensity: 0.65,
  idleDwellDuration: 1.0,
  autoCheckUpdates: true,
};

export interface PersistedPayload {
  activities: ActivityRecord[];
  settings: AppSettings;
}

export async function loadData(): Promise<PersistedPayload> {
  try {
    const raw = await invoke<string>('load_persisted_data');
    if (raw && raw !== '{}') {
      const parsed = JSON.parse(raw);
      return {
        activities: parsed.activities || [],
        settings: { ...DEFAULT_SETTINGS, ...(parsed.settings || {}) },
      };
    }
  } catch {
    // Fallback to localStorage in web dev mode
    const local = localStorage.getItem('nilaikinerja_data');
    if (local) {
      try {
        const parsed = JSON.parse(local);
        return {
          activities: parsed.activities || [],
          settings: { ...DEFAULT_SETTINGS, ...(parsed.settings || {}) },
        };
      } catch {}
    }
  }

  return {
    activities: [],
    settings: DEFAULT_SETTINGS,
  };
}

export async function saveData(payload: PersistedPayload): Promise<void> {
  const jsonStr = JSON.stringify(payload, null, 2);
  try {
    await invoke('save_persisted_data', { jsonContent: jsonStr });
  } catch {
    localStorage.setItem('nilaikinerja_data', jsonStr);
  }
}
