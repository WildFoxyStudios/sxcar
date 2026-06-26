import { Platform } from "react-native";
import * as SecureStore from "expo-secure-store";

export type Tokens = { access: string; refresh: string };
const KEY = "px.tokens";

const webStore = {
  getItem: (k: string) => Promise.resolve(globalThis.localStorage?.getItem(k) ?? null),
  setItem: (k: string, v: string) => Promise.resolve(globalThis.localStorage?.setItem(k, v)),
  removeItem: (k: string) => Promise.resolve(globalThis.localStorage?.removeItem(k)),
};

const store = Platform.OS === "web"
  ? webStore
  : {
      getItem: (k: string) => SecureStore.getItemAsync(k),
      setItem: (k: string, v: string) => SecureStore.setItemAsync(k, v),
      removeItem: (k: string) => SecureStore.deleteItemAsync(k),
    };

export async function getTokens(): Promise<Tokens | null> {
  const raw = await store.getItem(KEY);
  return raw ? (JSON.parse(raw) as Tokens) : null;
}
export async function setTokens(t: Tokens): Promise<void> {
  await store.setItem(KEY, JSON.stringify(t));
}
export async function clearTokens(): Promise<void> {
  await store.removeItem(KEY);
}
