import { deepStrictEqual as equal } from "node:assert/strict";
import { activityCopy, type ActivityFacts } from "./activity-copy.ts";

const you = "you",
  alex = "alex",
  connor = "connor",
  tyler = "tyler",
  sammy = "sammy",
  jordan = "jordan",
  taylor = "taylor";
function expect(
  e: ActivityFacts,
  statement: string,
  dollarLine: string | null = null,
  viewer = you,
  viewerName = "",
) {
  equal(activityCopy(e, viewer, viewerName), { statement, dollarLine });
}

// Same cases as ios/TripSplitTests/ActivityCopyTests.swift, including views that never receive a push.
const base = { actorId: alex, actorName: "Alex", tripName: "Coast Road" };
Deno.test("trip and member statements match ActivityCopyTests", () => {
  expect(
    { ...base, kind: "trip_created", actorId: you, actorName: "Alex Kim" },
    'You created the trip "Coast Road"',
  );
  expect(
    { ...base, kind: "trip_created" },
    'Alex created the trip "Coast Road"',
  );
  expect({ ...base, kind: "member_joined" }, 'Alex joined "Coast Road"');
  expect({
    ...base,
    kind: "member_joined",
    actorId: you,
    actorName: "Alex Kim",
  }, 'You joined "Coast Road"');
  expect(
    { ...base, kind: "member_joined", actorName: "" },
    'Someone joined "Coast Road"',
  );
  for (
    const [kind, verb] of [["trip_deleted", "deleted"], [
      "trip_undeleted",
      "restored",
    ]]
  ) {
    expect({
      ...base,
      kind,
      actorId: sammy,
      actorName: "Sammy",
      tripName: "Orlando 2027",
      deltas: { [you]: -5000 },
    }, `Sammy ${verb} the trip "Orlando 2027"`);
    expect({
      ...base,
      kind,
      actorId: you,
      actorName: "Alex Kim",
      tripName: "Orlando 2027",
    }, `You ${verb} the trip "Orlando 2027"`);
  }
});

Deno.test("expense statements and deltas match ActivityCopyTests", () => {
  expect(
    {
      ...base,
      kind: "expense_added",
      actorId: connor,
      actorName: "Connor",
      subject: "Airbnb",
      deltas: { [you]: -3600 },
    },
    'Connor added "Airbnb" in "Coast Road"',
    "You owe $36",
  );
  expect(
    {
      ...base,
      kind: "expense_added",
      actorId: you,
      actorName: "Alex Kim",
      tripName: "Night Market",
      subject: "Lyft",
      deltas: { [you]: 5000 },
    },
    'You added "Lyft" in "Night Market"',
    "You get back $50",
  );
  expect(
    {
      ...base,
      kind: "expense_updated",
      actorId: tyler,
      actorName: "Tyler",
      tripName: "Lake House",
      subject: "Costco",
      deltas: { [you]: 11740 },
    },
    'Tyler updated "Costco" in "Lake House"',
    "You get back $117.40",
  );
  expect(
    {
      ...base,
      kind: "expense_deleted",
      actorId: tyler,
      actorName: "Tyler",
      tripName: "Lake House",
      subject: "Costco",
      deltas: { [you]: 5000 },
    },
    'Tyler deleted "Costco" in "Lake House"',
    "You get back $50",
  );
  expect(
    {
      ...base,
      kind: "expense_restored",
      actorId: tyler,
      actorName: "Tyler",
      tripName: "Lake House",
      subject: "Costco",
      deltas: { [you]: -5000 },
    },
    'Tyler restored "Costco" in "Lake House"',
    "You owe $50",
  );
  expect({
    ...base,
    kind: "expense_added",
    actorId: you,
    tripName: "Night Market",
    subject: "Lyft",
    expensePayerId: you,
    expenseAmountCents: 10000,
    viewerShareCents: 5000,
  }, 'You added "Lyft" in "Night Market"');
});

const lyft = [
  {
    note: "You paid; you and Alex equally",
    delta: 5000,
    youPaid: true,
    share: 5000,
    line: "You get back $50",
  },
  {
    note: "You paid; only you in the split",
    delta: 0,
    youPaid: true,
    share: 10000,
    line: "You paid $100",
  },
  {
    note: "You paid; Alex and Jordan only",
    delta: 10000,
    youPaid: true,
    share: null,
    line: "You get back $100",
  },
  {
    note: "Alex paid; you and Alex equally",
    delta: -5000,
    youPaid: false,
    share: 5000,
    line: "You owe $50",
  },
  {
    note: "Alex paid; you not in the split",
    delta: 0,
    youPaid: false,
    share: null,
    line: null,
  },
];
for (
  const [kind, verb] of [
    ["expense_added", "added"],
    ["expense_updated", "updated"],
    ["expense_deleted", "deleted"],
    ["expense_restored", "restored"],
  ]
) {
  for (const row of lyft) {
    Deno.test(`${kind}: ${row.note} (ActivityCopyTests Lyft matrix)`, () => {
      expect(
        {
          kind,
          actorId: connor,
          actorName: "Connor",
          tripName: "Night Market",
          subject: "Lyft",
          deltas: row.delta ? { [you]: row.delta } : {},
          expensePayerId: row.youPaid ? you : alex,
          expenseAmountCents: 10000,
          viewerShareCents: row.share,
        },
        `Connor ${verb} "Lyft" in "Night Market"`,
        row.line,
      );
    });
  }
}

Deno.test("payment statements match ActivityCopyTests, using the payer rather than the logger", () => {
  const paid = {
    kind: "payment_logged",
    actorId: sammy,
    actorName: "Sammy",
    tripName: "Orlando 2027",
    deltas: { [sammy]: 51844, [you]: -51844 },
    payerId: sammy,
    payeeId: you,
    payerName: "Sammy",
    payeeName: "Alex Kim",
    amountCents: 51844,
  };
  expect(paid, 'Sammy paid you in "Orlando 2027"', "You received $518.44");
  expect(
    { ...paid, actorId: you, actorName: "Alex Kim" },
    'Sammy paid you in "Orlando 2027"',
    "You received $518.44",
  );
  const sent = {
    ...base,
    kind: "payment_logged",
    actorId: you,
    actorName: "Alex Kim",
    deltas: { [you]: 3000, [connor]: -3000 },
    payerId: you,
    payeeId: connor,
    payerName: "Alex Kim",
    payeeName: "Connor",
    amountCents: 3000,
  };
  expect(sent, 'You paid Connor $30 in "Coast Road"');
  expect(
    { ...sent, payeeName: "Connor Smith" },
    'You paid Connor S. $30 in "Coast Road"',
  );
  expect({
    ...base,
    kind: "payment_logged",
    actorId: tyler,
    actorName: "Tyler",
    tripName: "Lake House",
    payerId: tyler,
    payeeId: connor,
    payerName: "Tyler",
    payeeName: "Connor",
    amountCents: 3000,
  }, 'Tyler paid Connor in "Lake House"');
  expect(
    {
      ...paid,
      kind: "payment_deleted",
      deltas: { [sammy]: -51844, [you]: 51844 },
    },
    'Sammy removed a payment in "Orlando 2027"',
    "You get back $518.44",
  );
  expect(
    {
      ...sent,
      kind: "payment_deleted",
      deltas: { [you]: -3000, [connor]: 3000 },
    },
    'You removed a payment in "Coast Road"',
    "You owe $30",
  );
  expect({
    ...base,
    kind: "payment_deleted",
    actorId: tyler,
    actorName: "Tyler",
    tripName: "Lake House",
    deltas: { [tyler]: -3000, [connor]: 3000 },
    payerId: tyler,
    payeeId: connor,
    amountCents: 3000,
  }, 'Tyler removed a payment in "Lake House"');
});

Deno.test("removal statements match ActivityCopyTests", () => {
  const removed = {
    ...base,
    kind: "member_removed",
    actorId: taylor,
    actorName: "Taylor",
    subject: "Jordan",
    removedId: jordan,
  };
  expect(removed, 'Taylor removed Jordan from "Coast Road"');
  expect(
    { ...removed, actorId: jordan, actorName: "Jordan" },
    'Jordan left "Coast Road"',
  );
  expect({
    ...removed,
    actorId: you,
    actorName: "Alex Kim",
    subject: "Alex Kim",
    removedId: you,
  }, 'You left "Coast Road"');
  expect(
    { ...removed, actorId: you, actorName: "Alex Kim" },
    'You removed Jordan from "Coast Road"',
  );
  expect(
    { ...removed, subject: "Alex Kim", removedId: you },
    'Taylor removed you from "Coast Road"',
  );
  expect(
    { ...removed, actorName: "Taylor Smith", subject: "Jordan Lee" },
    'Taylor S. removed Jordan L. from "Coast Road"',
  );
  expect(
    { ...removed, actorId: jordan, actorName: "Jordan", removedId: null },
    'Jordan left "Coast Road"',
  );
  expect(
    { ...removed, subject: "Alex Kim", removedId: null },
    'Taylor removed you from "Coast Road"',
    null,
    you,
    "Alex Kim",
  );
});

Deno.test("missing snapshots and unknown kinds don't invent copy", () => {
  expect({
    ...base,
    kind: "expense_added",
    subject: "Lyft",
    expensePayerId: you,
    viewerShareCents: 10000,
  }, 'Alex added "Lyft" in "Coast Road"');
  expect({ ...base, kind: "future_event" }, "");
});
