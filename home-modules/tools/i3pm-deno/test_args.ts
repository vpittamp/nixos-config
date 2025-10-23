import { parseArgs } from "jsr:@std/cli@1/parse-args";

const args = ["test-mvp", "--project=nixos"];
const parsed = parseArgs(args, {
  string: ["project"],
  boolean: ["json"],
  stopEarly: true,
});

console.log("Parsed:", JSON.stringify(parsed, null, 2));
console.log("Project:", parsed.project);
