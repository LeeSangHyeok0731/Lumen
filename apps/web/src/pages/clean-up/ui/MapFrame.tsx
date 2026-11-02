import type { AssessProgressView } from "@lumen/api-client";
import { useQuery } from "@tanstack/react-query";
import { stagePercent } from "@/entities/scan-session";
import { QUERY_KEYS, useTransport } from "@/shared/api";
import { countFormat, useI18n } from "@/shared/i18n";
import { formatBytes } from "@/shared/lib";
import { readPermille } from "../model/resolving";

/**
 * The map's frame before there is a map (docs/design/visual-language.md,
 * understanding resolving): one dashed "Not read yet" region before a scan;
 * while it reads, a hatch fills against the disk's used space, then a tinted
 * fill carries the assessment's progress in the same frame.
 */
export function MapFrame({
  read,
  deciding = false,
  assessmentProgress = null,
}: {
  /** Bytes read so far; `null` before a scan. */ readonly read: string | null;
  readonly deciding?: boolean;
  readonly assessmentProgress?: AssessProgressView | null;
}) {
  const { locale, m } = useI18n();
  const transport = useTransport();
  const disk = useQuery({
    queryKey: QUERY_KEYS.disk,
    queryFn: () => transport.disk(),
    retry: false,
    enabled: read !== null,
  });
  const frame = "map-frame relative h-[200px] min-[640px]:h-[280px]";
  if (read === null) {
    return (
      <div aria-hidden="true" className={frame}>
        <span className="topo-label">{m.results.map.notReadYet}</span>
      </div>
    );
  }
  const permille = readPermille(disk.data ?? null, read);
  const percent = deciding ? stagePercent(assessmentProgress) : null;
  const stage = assessmentProgress
    ? m.scanning.stages[assessmentProgress.stage]
    : m.scanning.deciding;
  const units =
    assessmentProgress?.total === null || !assessmentProgress
      ? null
      : m.scanning.processed(
          countFormat(locale)(assessmentProgress.completed),
          countFormat(locale)(assessmentProgress.total),
        );
  const label = deciding ? stage : m.scanning.progress;
  const valueText = deciding
    ? [stage, percent === null ? null : m.scanning.stagePercent(percent), units]
        .filter(Boolean)
        .join(" · ")
    : m.scanning.readSoFar(formatBytes(read));
  return (
    <div
      role="progressbar"
      aria-label={label}
      aria-valuemin={deciding ? 0 : undefined}
      aria-valuemax={deciding ? 100 : undefined}
      aria-valuenow={percent ?? undefined}
      aria-valuetext={valueText}
      data-phase={deciding ? "assessment" : "scan"}
      className={frame}
    >
      {deciding ? (
        <div
          className="map-assessment absolute inset-y-0 left-0"
          data-indeterminate={percent === null ? "true" : undefined}
          style={percent === null ? undefined : { width: `${percent}%` }}
        />
      ) : permille !== null ? (
        <div
          className="map-read absolute inset-y-0 left-0"
          style={{ width: `${permille / 10}%` }}
        />
      ) : null}
      <span className="topo-label relative z-10 w-fit bg-canvas tabular-nums">
        {deciding ? (
          <>
            <span>{stage}</span>
            {(percent !== null || units !== null) && (
              <span>
                {[percent === null ? null : m.scanning.stagePercent(percent), units]
                  .filter(Boolean)
                  .join(" · ")}
              </span>
            )}
          </>
        ) : (
          label && <span>{valueText}</span>
        )}
      </span>
    </div>
  );
}
