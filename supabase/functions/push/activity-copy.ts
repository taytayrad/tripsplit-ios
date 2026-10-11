// Port of ActivityCopy.swift. The cases in activity-copy_test.ts mirror ActivityCopyTests.
export interface ActivityFacts {
  kind: string;
  actorId: string;
  actorName: string;
  tripName: string;
  subject?: string | null;
  removedId?: string | null;
  deltas?: Record<string, number>;
  expensePayerId?: string | null;
  expenseAmountCents?: number | null;
  viewerShareCents?: number | null;
  payerId?: string | null;
  payeeId?: string | null;
  payerName?: string | null;
  payeeName?: string | null;
  amountCents?: number | null;
}

function shown(name: string): string {
  const words = name.trim().split(/\s+/u).filter(Boolean);
  if (words.length < 2) return words[0] ?? "";
  // Swift's first Character is a grapheme, including composed initials.
  const initial = new Intl.Segmenter("en", { granularity: "grapheme" })
    .segment(words.at(-1)!)[Symbol.iterator]().next().value!.segment;
  return `${words[0]} ${initial}.`;
}

function person(
  name: string | null | undefined,
  you: boolean,
  leading: boolean,
): string {
  return you ? (leading ? "You" : "you") : shown(name ?? "") || "Someone";
}

function money(cents: number): string {
  return new Intl.NumberFormat("en-US", {
    style: "currency",
    currency: "USD",
    minimumFractionDigits: cents % 100 === 0 ? 0 : 2,
    maximumFractionDigits: cents % 100 === 0 ? 0 : 2,
  }).format(Math.abs(cents) / 100);
}

export function activityCopy(
  e: ActivityFacts,
  viewer: string,
  viewerName = "",
) {
  const trip = `"${e.tripName}"`;
  const actor = person(e.actorName, e.actorId === viewer, true);
  const delta = e.deltas?.[viewer] ?? 0;
  let statement = "";
  let dollarLine: string | null = null;
  switch (e.kind) {
    case "trip_created":
      statement = `${actor} created the trip ${trip}`;
      break;
    case "member_joined":
      statement = `${actor} joined ${trip}`;
      break;
    case "expense_added":
    case "expense_updated":
    case "expense_deleted":
    case "expense_restored": {
      const verb = {
        expense_added: "added",
        expense_updated: "updated",
        expense_deleted: "deleted",
        expense_restored: "restored",
      }[e.kind];
      statement = `${actor} ${verb} "${e.subject ?? ""}" in ${trip}`;
      if (delta < 0) dollarLine = `You owe ${money(delta)}`;
      else if (delta > 0) dollarLine = `You get back ${money(delta)}`;
      else if (
        e.expensePayerId === viewer && e.expenseAmountCents != null &&
        e.viewerShareCents === e.expenseAmountCents
      ) {
        dollarLine = `You paid ${money(e.expenseAmountCents)}`;
      }
      break;
    }
    case "payment_logged":
      if (e.payeeId === viewer && e.payerId !== viewer) {
        statement = `${person(e.payerName, false, true)} paid you in ${trip}`;
        if (e.amountCents != null) {
          dollarLine = `You received ${money(e.amountCents)}`;
        }
      } else if (e.payerId === viewer) {
        const amount = e.amountCents == null ? "" : ` ${money(e.amountCents)}`;
        statement = `You paid ${
          person(e.payeeName, false, false)
        }${amount} in ${trip}`;
      } else {statement = `${person(e.payerName, false, true)} paid ${
          person(e.payeeName, false, false)
        } in ${trip}`;}
      break;
    case "payment_deleted":
      statement = `${actor} removed a payment in ${trip}`;
      if (delta > 0) dollarLine = `You get back ${money(delta)}`;
      else if (delta < 0) dollarLine = `You owe ${money(delta)}`;
      break;
    case "trip_deleted":
      statement = `${actor} deleted the trip ${trip}`;
      break;
    case "trip_undeleted":
      statement = `${actor} restored the trip ${trip}`;
      break;
    case "member_removed": {
      const left = e.removedId != null
        ? e.removedId === e.actorId
        : !!e.subject && e.subject === e.actorName;
      const removedYou = e.removedId != null
        ? e.removedId === viewer
        : !!e.subject && e.subject === viewerName;
      statement = left
        ? `${actor} left ${trip}`
        : `${actor} removed ${
          person(e.subject, removedYou, false)
        } from ${trip}`;
      break;
    }
  }
  return { statement, dollarLine };
}
