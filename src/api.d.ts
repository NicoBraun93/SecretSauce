export {};
declare global {
  interface Window {
    api: {
      shell: {
        path: () => Promise<string>;
        read: () => Promise<{ path: string; vars: { key: string; value: string }[] }>;
        upsert: (key: string, value: string) => Promise<boolean>;
        delete: (key: string) => Promise<boolean>;
      };
      env: {
        pick: () => Promise<string | null>;
        create: () => Promise<string | null>;
        read: (filePath: string) => Promise<{ key: string; value: string }[]>;
        write: (filePath: string, vars: { key: string; value: string }[]) => Promise<boolean>;
        system: () => Promise<{ key: string; value: string }[]>;
      };
      keychain: {
        list: () => Promise<string[]>;
        get: (key: string) => Promise<string | null>;
        set: (key: string, value: string) => Promise<boolean>;
        delete: (key: string) => Promise<boolean>;
      };
      launchd: {
        list: () => Promise<{
          label: string;
          filePath: string;
          vars: { key: string; value: string }[];
          program: string;
          loaded: boolean;
          pid: number | null;
          lastExitCode?: number;
        }[]>;
        upsert: (filePath: string, key: string, value: string) => Promise<boolean>;
        delete: (filePath: string, key: string) => Promise<boolean>;
        control: (action: "load" | "unload" | "start" | "stop", filePath: string, label: string) => Promise<boolean>;
      };
    };
  }
}
