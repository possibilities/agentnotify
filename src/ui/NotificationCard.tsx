import type { NotificationMessage } from "./types";

interface NotificationCardProps {
  notification: NotificationMessage;
  dismissing: boolean;
  onDismiss(id: number): void;
}

export function safeLink(value: string | null): string | null {
  if (!value) return null;
  try {
    const url = new URL(value);
    return url.protocol === "http:" || url.protocol === "https:" ? url.href : null;
  } catch {
    return null;
  }
}

export function formatLocalTime(value: string): string {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value;
  return new Intl.DateTimeFormat(undefined, {
    dateStyle: "medium",
    timeStyle: "short",
  }).format(date);
}

function Tag({ label, value }: { label: string; value: string }) {
  return (
    <span className="tag">
      <span>{label}</span>
      {value}
    </span>
  );
}

export function NotificationCard({ notification, dismissing, onDismiss }: NotificationCardProps) {
  const dismissed = notification.dismissed_at !== null;
  const link = safeLink(notification.open_url);

  return (
    <article className={`notification-card${dismissed ? " is-dismissed" : ""}`}>
      <div className="card-heading">
        <div className="title-block">
          <span className="message-id">#{notification.id}</span>
          <h2>{notification.title || "Untitled notification"}</h2>
        </div>
        <time dateTime={notification.timestamp} title={notification.timestamp}>
          {formatLocalTime(notification.timestamp)}
        </time>
      </div>

      <p className="message-body">{notification.message}</p>

      <div className="card-footer">
        <div className="metadata">
          <Tag label="method" value={notification.method} />
          {notification.sound && <Tag label="sound" value={notification.sound} />}
          {notification.group_id && <Tag label="group" value={notification.group_id} />}
          {notification.open_url &&
            (link ? (
              <a className="tag link-tag" href={link} target="_blank" rel="noreferrer">
                <span>open</span>
                link ↗
              </a>
            ) : (
              <Tag label="open" value="unavailable" />
            ))}
        </div>
        {dismissed ? (
          <span className="dismissed-label">Dismissed</span>
        ) : (
          <button
            className="dismiss-button"
            type="button"
            disabled={dismissing}
            onClick={() => onDismiss(notification.id)}
            aria-label={`Dismiss ${notification.title || `notification ${notification.id}`}`}
          >
            {dismissing ? "Dismissing…" : "Dismiss"}
          </button>
        )}
      </div>
    </article>
  );
}
