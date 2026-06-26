export type TokenPair = { access: string; refresh: string };
export type RegisterReq = { email: string; password: string; dob: string; consents: string[] };
export type LoginReq = { email: string; password: string };
