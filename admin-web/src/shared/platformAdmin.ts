export function getAdminEmailAllowlist(): string[] {
  const raw =
    import.meta.env.VITE_ADMIN_EMAILS?.trim() || 'passwordsaver@gryzion.com';
  return raw
    .split(',')
    .map((e: string) => e.trim().toLowerCase())
    .filter(Boolean);
}

export function isPlatformAdminEmail(email: string | null | undefined): boolean {
  if (!email?.trim()) return false;
  return getAdminEmailAllowlist().includes(email.trim().toLowerCase());
}
