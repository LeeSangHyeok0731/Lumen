import { type ReactNode, useId } from "react";
import { useI18n } from "@/shared/i18n";
import { Bytes } from "@/shared/ui";
import type { CandidateSummary, Status } from "../model/summary";
import { DecisionMark } from "./DecisionMark";

const ORDER: readonly Status[] = ["keep", "review", "command", "quarantine"];

const CHOICE =
  "relative cursor-pointer border-b-2 border-transparent py-3 transition-colors hover:border-line-strong has-checked:border-accent has-focus-visible:outline-2 has-focus-visible:outline-accent motion-reduce:transition-none";

/** A status as a link: the same look, with the link's own focus ring. */
const LINK =
  "block border-b-2 border-transparent py-3 transition-colors hover:border-line-strong focus-visible:outline-2 focus-visible:outline-accent motion-reduce:transition-none";

/** How the statuses are offered: as one filter, or each as a link elsewhere. */
export type DecisionChoice =
  | {
      readonly kind: "filter";
      readonly selected: Status | null;
      /** A status, or `null` for "All". */
      readonly onSelect: (status: Status | null) => void;
      /** Offer "All" as the first choice. */
      readonly withAll?: boolean;
    }
  | {
      readonly kind: "link";
      /** `content` inside a link to this status's items, with `className`. */
      readonly link: (status: Status, content: ReactNode, className: string) => ReactNode;
    };

/** A status's name, mark and figures. */
function Figure({
  label,
  mark,
  bytes,
  items,
}: {
  readonly label: string;
  readonly mark: ReactNode;
  readonly bytes: string;
  readonly items: number;
}) {
  const { m } = useI18n();
  return (
    <>
      <span className="flex items-center gap-2 text-[13px] text-ink-2">
        {mark}
        {label}
      </span>
      <span className="mt-1 flex flex-wrap items-baseline gap-x-2">
        <span className="text-figure font-medium text-ink tabular-nums">
          <Bytes value={bytes} />
        </span>
        <span className="text-[12px] text-ink-3">{m.common.items(items)}</span>
      </span>
    </>
  );
}

/**
 * A single composition of assessed candidates, never a claim about the whole
 * disk. As a filter, each status is a choice; with `withAll`, "All" comes
 * first and is chosen while `selected` is null, so the legend is the one
 * status filter. As links (where choosing means going to another place), each
 * status is a link, so arrow keys never navigate.
 */
export function DecisionMap({
  summary,
  choice,
  accessory,
  track = true,
}: {
  readonly summary: CandidateSummary;
  readonly choice: DecisionChoice;
  /** Beside the legend: a glossary tip. */
  readonly accessory?: ReactNode;
  /** Draw the composition as a bar; off where a map above already draws it. */
  readonly track?: boolean;
}) {
  const { m } = useI18n();
  const name = useId();
  const title = useId();
  const total = ORDER.reduce((sum, status) => sum + BigInt(summary[status].bytes), 0n);
  const withAll = choice.kind === "filter" && choice.withAll === true;
  const legend = (
    <>
      {m.workspace.assessed}
      {accessory}
    </>
  );
  const LEGEND = "mb-3 flex items-center gap-2 text-[12px] font-medium text-ink-2";
  const GRID = `grid grid-cols-2 gap-x-5 ${withAll ? "min-[640px]:grid-cols-5" : "min-[640px]:grid-cols-4"}`;
  const bar = track && (
    <div aria-hidden="true" className="decision-track">
      {ORDER.map((status) => (
        <span
          key={status}
          className="decision-segment"
          data-status={status}
          style={{
            width: `${total === 0n ? 0 : Number((BigInt(summary[status].bytes) * 1000n) / total) / 10}%`,
          }}
        />
      ))}
    </div>
  );
  const figure = (status: Status) => (
    <Figure
      label={m.results.status[status]}
      mark={<DecisionMark status={status} />}
      bytes={summary[status].bytes}
      items={summary[status].items.length}
    />
  );
  switch (choice.kind) {
    case "link":
      return (
        <div className="min-w-0">
          <p id={title} className={LEGEND}>
            {legend}
          </p>
          {bar}
          <ul aria-labelledby={title} className={GRID}>
            {ORDER.map((status) => (
              <li key={status}>{choice.link(status, figure(status), LINK)}</li>
            ))}
          </ul>
        </div>
      );
    case "filter":
      return (
        <fieldset className="min-w-0">
          <legend className={LEGEND}>{legend}</legend>
          {bar}
          <div className={GRID}>
            {withAll && (
              <label className={CHOICE}>
                <input
                  type="radio"
                  name={name}
                  checked={choice.selected === null}
                  onChange={() => choice.onSelect(null)}
                  className="sr-only"
                />
                <Figure
                  label={m.results.filters.all}
                  mark={null}
                  bytes={total.toString()}
                  items={ORDER.reduce((n, status) => n + summary[status].items.length, 0)}
                />
              </label>
            )}
            {ORDER.map((status) => (
              <label key={status} className={CHOICE}>
                <input
                  type="radio"
                  name={name}
                  checked={choice.selected === status}
                  onChange={() => choice.onSelect(status)}
                  className="sr-only"
                />
                {figure(status)}
              </label>
            ))}
          </div>
        </fieldset>
      );
  }
}
