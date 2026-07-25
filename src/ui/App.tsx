import { useEffect, useId, useMemo, useState } from "react";
import { NotificationCard } from "./NotificationCard";
import type { MessageFilter } from "./types";
import { useNotifications } from "./useNotifications";

const FILTERS: MessageFilter[] = ["all", "active", "dismissed"];

export default function App() {
  const [query, setQuery] = useState("");
  const [search, setSearch] = useState("");
  const [filter, setFilter] = useState<MessageFilter>("all");
  const titleId = useId();
  const { messages, loading, error, dismissing, dismiss, refresh } = useNotifications(search);

  useEffect(() => {
    const timeout = window.setTimeout(() => setSearch(query), 250);
    return () => window.clearTimeout(timeout);
  }, [query]);

  const visible = useMemo(
    () =>
      messages.filter((message) => {
        if (filter === "active") return message.dismissed_at === null;
        if (filter === "dismissed") return message.dismissed_at !== null;
        return true;
      }),
    [filter, messages],
  );
  const activeCount = messages.filter((message) => message.dismissed_at === null).length;

  return (
    <main>
      <header className="app-header">
        <div className="header-inner">
          <a className="wordmark" href="/" aria-label="agentnotify home">
            agentnotify
          </a>
          <span className="system-status">
            <span className="status-dot" aria-hidden="true" />
            notification log
          </span>
        </div>
      </header>

      <section className="log-shell" aria-labelledby={titleId}>
        <div className="intro">
          <div>
            <p className="eyebrow">History</p>
            <h1 id={titleId}>Notifications</h1>
            <p className="subtitle">
              A quiet record of messages sent by your local agents and scripts.
            </p>
          </div>
          <output className="count-block">
            <strong>{activeCount}</strong>
            <span>active</span>
          </output>
        </div>

        <div className="controls">
          <div className="filter-group">
            {FILTERS.map((value) => (
              <button
                type="button"
                key={value}
                aria-pressed={filter === value}
                onClick={() => setFilter(value)}
              >
                {value}
              </button>
            ))}
          </div>
          <label className="search-field">
            <span className="sr-only">Search notifications</span>
            <svg aria-hidden="true" viewBox="0 0 24 24">
              <circle cx="11" cy="11" r="6.5" />
              <path d="m16 16 4 4" />
            </svg>
            <input
              type="search"
              value={query}
              onChange={(event) => setQuery(event.target.value)}
              placeholder="Search title or message"
            />
          </label>
        </div>

        {error && (
          <div className="state-panel error-panel" role="alert">
            <div>
              <strong>Couldn’t load the log</strong>
              <p>{error}</p>
            </div>
            <button type="button" onClick={() => void refresh()}>
              Try again
            </button>
          </div>
        )}

        {loading && messages.length === 0 ? (
          <div className="state-panel" aria-live="polite">
            <span className="loading-mark" aria-hidden="true" />
            <div>
              <strong>Loading notifications</strong>
              <p>Reading the local message log.</p>
            </div>
          </div>
        ) : visible.length === 0 && !error ? (
          <div className="state-panel empty-panel">
            <strong>
              {query
                ? "No matching notifications"
                : `No ${filter === "all" ? "" : `${filter} `}notifications`}
            </strong>
            <p>
              {query ? "Try a different search." : "New messages will appear here automatically."}
            </p>
          </div>
        ) : (
          <div className="notification-list" aria-live="polite">
            {visible.map((notification) => (
              <NotificationCard
                key={notification.id}
                notification={notification}
                dismissing={dismissing === notification.id}
                onDismiss={(id) => void dismiss(id)}
              />
            ))}
          </div>
        )}
      </section>
    </main>
  );
}
