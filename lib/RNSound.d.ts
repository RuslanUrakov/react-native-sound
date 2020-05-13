export declare const RNSound: {
    preload(source: string): Promise<void>;
    play(options?: {
        volume?: number;
        loops?:boolean;
    }): Promise<void>;
    stop(): Promise<void>;
    pause(): Promise<void>;
    resume(): Promise<void>;
    setVolume(volume: number): Promise<void>;
};    
