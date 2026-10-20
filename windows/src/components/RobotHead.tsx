import React, { useEffect, useRef } from 'react';
import { RobotState } from '../types';

declare global {
  interface Window {
    RobotHead?: {
      create: (container: HTMLElement, options: any) => any;
    };
  }
}

interface RobotHeadProps {
  state?: RobotState;
  size?: number;
  shape?: 'rectangle' | 'circle' | 'pill';
  color?: string;
  trimColor?: string;
  screenColor?: string;
  antenna?: boolean;
  floorShadow?: boolean;
  interactive?: boolean;
  onClick?: () => void;
  className?: string;
}

export const RobotHead: React.FC<RobotHeadProps> = ({
  state = 'idle',
  size = 120,
  shape = 'rectangle',
  color = '#2563EB',
  trimColor = '#93A6C8',
  screenColor = '#E8F2FF',
  antenna = true,
  floorShadow = true,
  interactive = true,
  onClick,
  className = '',
}) => {
  const containerRef = useRef<HTMLDivElement>(null);
  const botRef = useRef<any>(null);

  useEffect(() => {
    if (!containerRef.current || !window.RobotHead) return;

    containerRef.current.innerHTML = '';
    try {
      const bot = window.RobotHead.create(containerRef.current, {
        size,
        shape,
        state,
        color,
        trimColor,
        screenColor,
        antenna,
        floorShadow,
        speed: 1,
        interactive,
      });
      botRef.current = bot;
    } catch (e) {
      console.error('Failed to initialize 3D RobotHead:', e);
    }

    return () => {
      botRef.current = null;
      if (containerRef.current) {
        containerRef.current.innerHTML = '';
      }
    };
  }, [size, shape, color, trimColor, screenColor, antenna, floorShadow, interactive]);

  useEffect(() => {
    if (botRef.current && botRef.current.setState) {
      botRef.current.setState(state);
    }
  }, [state]);

  const handleClick = () => {
    if (botRef.current && botRef.current.poke) {
      botRef.current.poke();
    }
    if (onClick) {
      onClick();
    }
  };

  return (
    <div
      ref={containerRef}
      onClick={handleClick}
      className={`cursor-pointer select-none transition-transform hover:scale-105 active:scale-95 ${className}`}
      style={{
        width: size,
        height: size,
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
      }}
      title="Klik robot untuk interaksi lompat & putar!"
    />
  );
};
