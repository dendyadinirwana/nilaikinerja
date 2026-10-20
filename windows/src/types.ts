export type RobotState =
  | 'idle'
  | 'working'
  | 'thinking'
  | 'searching'
  | 'speaking'
  | 'listening'
  | 'happy'
  | 'error'
  | 'sleeping';

export type WindowMode = 'idle' | 'hover' | 'expanded';

export type ScreenTab = 'home' | 'add' | 'history' | 'ai' | 'settings';

export interface AttachmentItem {
  id: string;
  name: string;
  size: number;
  path: string;
  kind: 'doc' | 'presentation' | 'spreadsheet' | 'pdf' | 'image' | 'text' | 'unknown';
  format: string;
  verified: boolean;
}

export interface ActivityRecord {
  id: string;
  title: string;
  detail: string;
  startTime: string; // "09:00"
  endTime: string;   // "10:30"
  date: string;      // "YYYY-MM-DD"
  durationMinutes: number;
  attachments: AttachmentItem[];
  createdAt: number;
}

export interface AppSettings {
  workStartHour: number;
  workStartMinute: number;
  workEndHour: number;
  workEndMinute: number;
  reminderIntervalMinutes: number;
  reminderEnabled: boolean;
  aiBaseURL: string;
  aiModel: string;
  aiApiKey: string;
  idleGlowIntensity: number;
  idleDwellDuration: number;
  autoCheckUpdates: boolean;
}

export interface ValidationVerdict {
  ok: boolean;
  reason: string;
  file_name: string;
  file_size: number;
  kind: 'doc' | 'presentation' | 'spreadsheet' | 'pdf' | 'image' | 'text' | 'unknown';
  format: string;
}
