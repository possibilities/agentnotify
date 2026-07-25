export interface NotificationMessage {
  id: number;
  timestamp: string;
  title: string;
  message: string;
  sound: string | null;
  group_id: string | null;
  open_url: string | null;
  method: string;
  dismissed_at: string | null;
}

export type MessageFilter = "all" | "active" | "dismissed";
