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
    };
  }
}
