// 03_bulk_and_index_demo.js
// Insert 40,000 portal_activity documents in batches, then compare a
// COLLSCAN (forced with hint({$natural:1})) against an IXSCAN using a
// compound index. Prints a small BEFORE/AFTER table.
//
// Run with:   mongosh pensions 03_bulk_and_index_demo.js
// Requires:   01_setup.js already run (so the validator is in place).

db = db.getSiblingDB("pensions");

// Drop just the bulk test documents (keep the small seed rows from
// 02_data_and_queries.js if present, or start empty if not).
db.portal_activity.deleteMany({ bulk: true });

// Drop the compound index if a previous run left it, so the BEFORE phase
// really is a COLLSCAN. Wrapped in try/catch per the brief.
try { db.portal_activity.dropIndex("bulk_rsa_occurred_1"); } catch (e) { /* index not created yet: fine */ }

// ---- Helper: produce one synthetic bulk document.
function makeBulkDoc(i) {
  // Cycle through a small set of RSA numbers so the compound index has
  // something selective to bite on.
  var rsa = "LHP/RSA/" + String(1 + (i % 50)).padStart(6, "0");
  // Spread occurred_at over the last 365 days.
  var occurred = new Date(Date.now() - (i % 365) * 24 * 3600 * 1000 - (i % 86400) * 1000);
  if (i % 3 === 0) {
    return {
      _id: ObjectId(),
      rsa_number: rsa,
      activity_type: "LOGIN",
      login_method: (i % 2 === 0) ? "OTP" : "PASSWORD",
      occurred_at: occurred,
      ip_address: "41.58.0." + (i % 250),
      user_agent: "Mozilla/5.0 (Linux; Android 12; bulk)",
      status: "SUCCESS",
      duration_ms: Int32(100 + (i % 500)),
      bulk: true
    };
  } else {
    return {
      _id: ObjectId(),
      rsa_number: rsa,
      activity_type: "STATEMENT_VIEW",
      statement_period: "20" + (20 + (i % 5)) + "-" + String(1 + (i % 12)).padStart(2, "0"),
      occurred_at: occurred,
      ip_address: "41.58.0." + (i % 250),
      user_agent: "Mozilla/5.0 (Linux; Android 12; bulk)",
      status: "SUCCESS",
      duration_ms: Int32(100 + (i % 500)),
      bulk: true
    };
  }
}

// ---- Bulk insert: 40,000 documents in batches of 2,000.
var TOTAL = 40_000;
var BATCH = 2_000;
var inserted = 0;
var t0 = Date.now();
for (var b = 0; b < TOTAL; b += BATCH) {
  var docs = [];
  for (var i = 0; i < BATCH; i++) {
    docs.push(makeBulkDoc(b + i));
  }
  db.portal_activity.insertMany(docs, { ordered: false });
  inserted += BATCH;
}
var insertMs = Date.now() - t0;
print("Inserted " + inserted + " bulk documents in " + insertMs + " ms.");

// A typical query: all LOGIN events for ONE rsa_number, sorted by occurred_at desc.
var targetRsa = "LHP/RSA/000007";
var filter = { rsa_number: targetRsa, activity_type: "LOGIN", bulk: true };
var sort   = { occurred_at: -1 };

// ---- BEFORE: force a COLLSCAN with hint({$natural:1}).
print("\n--- BEFORE (COLLSCAN via hint({$natural:1})) ---");
var before = db.portal_activity
  .find(filter)
  .sort(sort)
  .limit(50)
  .hint({ $natural: 1 })
  .explain("executionStats");

var beforeLeaf  = walkStage(before.executionStats.executionStages) || before.executionStats.executionStages;
var beforeStage = beforeLeaf.stage;
var beforeDocs  = before.executionStats.totalDocsExamined;
var beforeTime  = before.executionStats.executionTimeMillis;
print("Stage BEFORE: " + beforeStage);
print("Docs BEFORE : " + beforeDocs);
print("Time ms BEFORE: " + beforeTime);

// ---- Create the compound index.
print("\n--- Creating compound index { rsa_number:1, activity_type:1, occurred_at:-1 } ---");
db.portal_activity.createIndex(
  { rsa_number: 1, activity_type: 1, occurred_at: -1 },
  { name: "bulk_rsa_occurred_1" }
);

// ---- AFTER: same query, but Mongo can use the new index.
print("\n--- AFTER (IXSCAN via compound index) ---");
var after = db.portal_activity
  .find(filter)
  .sort(sort)
  .limit(50)
  .explain("executionStats");

function walkStage(s) {
  if (!s) return null;
  if (s.stage === "IXSCAN" || s.stage === "COLLSCAN") return s;
  if (s.inputStage)  return walkStage(s.inputStage);
  if (s.inputStages) {
    for (var k = 0; k < s.inputStages.length; k++) {
      var r = walkStage(s.inputStages[k]);
      if (r) return r;
    }
  }
  return null;
}

var afterRoot   = after.executionStats.executionStages;
var afterLeaf   = walkStage(afterRoot) || afterRoot;
var afterStage  = afterLeaf.stage;
var afterDocs   = after.executionStats.totalDocsExamined;
var afterTime   = after.executionStats.executionTimeMillis;
print("Stage AFTER : " + afterStage);
print("Docs AFTER  : " + afterDocs);
print("Time ms AFTER: " + afterTime);

// ---- Summary table.
print("\n================ SUMMARY ================");
print("Metric        BEFORE                AFTER");
print("Stage         " + (beforeStage || "?") + "                " + (afterStage || "?"));
print("Docs examined " + beforeDocs + "                " + afterDocs);
print("Time (ms)     " + beforeTime + "                " + afterTime);

// ---- Cleanup the bulk rows + drop the index so the file is rerunnable.
db.portal_activity.deleteMany({ bulk: true });
try { db.portal_activity.dropIndex("bulk_rsa_occurred_1"); } catch (e) { print("dropIndex (post): " + e); }

print("\n03_bulk_and_index_demo.js: cleanup done. Bulk rows removed, compound index dropped.");
