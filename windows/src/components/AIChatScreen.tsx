import React, { useState, useRef, useEffect } from 'react';
import { Send, Bot, User, Sparkles, PlusCircle } from 'lucide-react';
import { AppSettings, RobotState } from '../types';

interface Message {
  role: 'user' | 'assistant';
  content: string;
}

interface AIChatScreenProps {
  settings: AppSettings;
  setRobotState: (s: RobotState) => void;
  onLogAsActivity: (text: string) => void;
}

export const AIChatScreen: React.FC<AIChatScreenProps> = ({
  settings,
  setRobotState,
  onLogAsActivity,
}) => {
  const [messages, setMessages] = useState<Message[]>([
    {
      role: 'assistant',
      content:
        'Halo! Saya Asisten AI NilaiKinerja. Saya siap membantu menyusun draf kegiatan harian, formulasi capaian output, atau merekap kinerja Anda. Ada yang bisa saya bantu?',
    },
  ]);
  const [input, setInput] = useState('');
  const [isLoading, setIsLoading] = useState(false);
  const scrollRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    scrollRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [messages]);

  const quickPrompts = [
    'Buatkan draf kegiatan penyusunan pedoman kerja',
    'Buat laporan rekap capaian kinerja harian ASN',
    'Formulasikan indikator target capaian kinerja bulanan',
  ];

  const handleSend = async (textToSend?: string) => {
    const prompt = (textToSend || input).trim();
    if (!prompt || isLoading) return;

    setInput('');
    const newMessages: Message[] = [...messages, { role: 'user', content: prompt }];
    setMessages(newMessages);
    setIsLoading(true);
    setRobotState('thinking');

    try {
      const endpoint = settings.aiBaseURL.replace(/\/+$/, '') + '/chat/completions';
      const headers: Record<string, string> = {
        'Content-Type': 'application/json',
      };
      if (settings.aiApiKey && settings.aiApiKey.trim()) {
        headers['Authorization'] = `Bearer ${settings.aiApiKey.trim()}`;
      }

      const res = await fetch(endpoint, {
        method: 'POST',
        headers,
        body: JSON.stringify({
          model: settings.aiModel || 'llama3',
          messages: [
            {
              role: 'system',
              content:
                'Anda adalah asisten AI profesional untuk penyusunan laporan capaian kinerja harian dan bulanan pegawai ASN. Jawab dengan ringkas, terstruktur, berbasis data, dan langsung aplikatif.',
            },
            ...newMessages,
          ],
          stream: false,
        }),
      });

      if (!res.ok) {
        throw new Error(`HTTP ${res.status}: Gagal menghubungi server AI (${settings.aiBaseURL})`);
      }

      const data = await res.json();
      const reply = data.choices?.[0]?.message?.content || 'Tidak ada balasan dari model.';

      setMessages((prev) => [...prev, { role: 'assistant', content: reply }]);
      setRobotState('speaking');
      setTimeout(() => setRobotState('idle'), 2000);
    } catch (e: any) {
      setMessages((prev) => [
        ...prev,
        {
          role: 'assistant',
          content: `⚠️ Terjadi kendala: ${e.message}\n\nPastikan runner lokal (seperti Ollama di port 11434 atau LM Studio) sudah aktif, atau sesuaikan Base URL di tab Pengaturan.`,
        },
      ]);
      setRobotState('error');
    } finally {
      setIsLoading(false);
    }
  };

  return (
    <div className="flex flex-col h-full p-4">
      {/* Top Bar */}
      <div className="flex items-center justify-between pb-3 border-b border-white/10 shrink-0">
        <div className="flex items-center gap-2">
          <Sparkles className="w-4 h-4 text-purple-400" />
          <span className="text-sm font-semibold text-white">Asisten AI NilaiKinerja</span>
        </div>
        <div className="flex items-center gap-2">
          <span className="px-2 py-0.5 rounded-full bg-white/10 text-[11px] font-mono text-white/70">
            {settings.aiModel}
          </span>
        </div>
      </div>

      {/* Messages list */}
      <div className="flex-1 overflow-y-auto space-y-3 py-3 pr-1 text-xs">
        {messages.map((m, idx) => (
          <div
            key={idx}
            className={`flex gap-2.5 ${m.role === 'user' ? 'justify-end' : 'justify-start'}`}
          >
            {m.role === 'assistant' && (
              <div className="w-6 h-6 rounded-full bg-purple-600/30 border border-purple-500/40 flex items-center justify-center shrink-0 mt-0.5">
                <Bot className="w-3.5 h-3.5 text-purple-300" />
              </div>
            )}

            <div
              className={`max-w-[85%] rounded-xl p-3 ${
                m.role === 'user'
                  ? 'bg-blue-600 text-white rounded-br-none'
                  : 'bg-white/5 border border-white/10 text-white/90 rounded-bl-none'
              }`}
            >
              <div className="whitespace-pre-wrap leading-relaxed">{m.content}</div>

              {m.role === 'assistant' && idx > 0 && (
                <button
                  onClick={() => onLogAsActivity(m.content)}
                  className="mt-2.5 pt-2 border-t border-white/10 flex items-center gap-1.5 text-[11px] text-blue-400 hover:text-blue-300 transition-colors"
                >
                  <PlusCircle className="w-3 h-3" />
                  Catat ke Kinerja
                </button>
              )}
            </div>

            {m.role === 'user' && (
              <div className="w-6 h-6 rounded-full bg-blue-600/30 border border-blue-500/40 flex items-center justify-center shrink-0 mt-0.5">
                <User className="w-3.5 h-3.5 text-blue-300" />
              </div>
            )}
          </div>
        ))}
        {isLoading && (
          <div className="flex items-center gap-2 text-white/40 text-xs">
            <div className="w-2 h-2 rounded-full bg-purple-400 animate-ping" />
            <span>AI sedang merumuskan draf kinerja...</span>
          </div>
        )}
        <div ref={scrollRef} />
      </div>

      {/* Quick Prompts */}
      <div className="flex items-center gap-1.5 overflow-x-auto py-2 shrink-0 no-scrollbar">
        {quickPrompts.map((q, idx) => (
          <button
            key={idx}
            onClick={() => handleSend(q)}
            className="shrink-0 px-2.5 py-1 rounded-full bg-white/5 hover:bg-white/10 border border-white/10 text-[11px] text-white/70 hover:text-white transition-colors"
          >
            {q}
          </button>
        ))}
      </div>

      {/* Input row - Standardized 36pt */}
      <div className="pt-2 border-t border-white/10 flex items-center gap-2 shrink-0">
        <input
          type="text"
          value={input}
          onChange={(e) => setInput(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === 'Enter') handleSend();
          }}
          placeholder="Tanyakan atau minta buatkan rumusan capaian kegiatan..."
          className="flex-1 h-[36px] bg-white/5 border border-white/10 rounded-lg px-3 text-xs text-white placeholder-white/30 focus:outline-none focus:border-purple-500 transition-colors"
          disabled={isLoading}
        />
        <button
          onClick={() => handleSend()}
          disabled={isLoading || !input.trim()}
          className="w-[36px] h-[36px] bg-purple-600 hover:bg-purple-500 disabled:opacity-40 rounded-lg flex items-center justify-center text-white transition-colors shrink-0 shadow-lg shadow-purple-500/20"
        >
          <Send className="w-4 h-4" />
        </button>
      </div>
    </div>
  );
};
