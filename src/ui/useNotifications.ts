import { useCallback, useEffect, useState } from "react";
import type { NotificationMessage } from "./types";

const POLL_INTERVAL = 10_000;

export function useNotifications(search: string) {
  const [messages, setMessages] = useState<NotificationMessage[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [dismissing, setDismissing] = useState<number | null>(null);

  const refresh = useCallback(
    async (signal?: AbortSignal) => {
      try {
        const parameters = new URLSearchParams({ limit: "200" });
        if (search.trim()) parameters.set("search", search.trim());
        const response = await fetch(`/api/messages?${parameters}`, { signal });
        if (!response.ok) throw new Error(`Request failed (${response.status})`);
        const result = (await response.json()) as NotificationMessage[];
        setMessages(result);
        setError(null);
      } catch (cause) {
        if (cause instanceof DOMException && cause.name === "AbortError") return;
        setError(cause instanceof Error ? cause.message : "Unable to load notifications");
      } finally {
        if (!signal?.aborted) setLoading(false);
      }
    },
    [search],
  );

  useEffect(() => {
    const controller = new AbortController();
    setLoading(true);
    void refresh(controller.signal);
    const interval = window.setInterval(() => void refresh(), POLL_INTERVAL);
    return () => {
      controller.abort();
      window.clearInterval(interval);
    };
  }, [refresh]);

  const dismiss = useCallback(async (id: number) => {
    setDismissing(id);
    try {
      const response = await fetch(`/api/messages/${id}/dismiss`, { method: "POST" });
      if (!response.ok) throw new Error(`Dismiss failed (${response.status})`);
      setMessages((current) =>
        current.map((message) =>
          message.id === id ? { ...message, dismissed_at: new Date().toISOString() } : message,
        ),
      );
      setError(null);
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "Unable to dismiss notification");
    } finally {
      setDismissing(null);
    }
  }, []);

  return { messages, loading, error, dismissing, dismiss, refresh };
}
