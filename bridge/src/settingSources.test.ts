import { expect, test } from "bun:test";
import { settingSources } from "./settingSources";

test("le fonti di TrustGate passano così come sono", () => {
  expect(settingSources(["user"])).toEqual(["user"]);
  expect(settingSources(["user", "project", "local"])).toEqual(["user", "project", "local"]);
});

test("senza un elenco valido, solo le impostazioni dell'utente", () => {
  for (const requested of [undefined, null, "project", [], ["user", "flag"], [1]]) {
    expect(settingSources(requested)).toEqual(["user"]);
  }
});
