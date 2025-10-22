import { describe, expect, it, beforeEach } from "vitest";
import { Cl } from "@stacks/transactions";

const accounts = simnet.getAccounts();
const deployer = accounts.get("deployer")!;
const address1 = accounts.get("wallet_1")!;
const address2 = accounts.get("wallet_2")!;
const address3 = accounts.get("wallet_3")!;

describe("WisdomNet Security Tests", () => {
  beforeEach(() => {
    simnet.mineEmptyBlock();
  });

  describe("Contract Initialization", () => {
    it("ensures simnet is well initialized", () => {
      expect(simnet.blockHeight).toBeDefined();
    });

    it("should have correct initial state", () => {
      const { result: isPaused } = simnet.callReadOnlyFn("WisdomNetcontract", "is-contract-paused", [], deployer);
      expect(isPaused).toBeBool(false);
    });
  });

  describe("Pause/Unpause Security", () => {
    it("should allow owner to pause contract", () => {
      const { result } = simnet.callPublicFn("WisdomNetcontract", "pause-contract", [], deployer);
      expect(result).toBeOk(Cl.bool(true));
    });

    it("should prevent non-owner from pausing", () => {
      const { result } = simnet.callPublicFn("WisdomNetcontract", "pause-contract", [], address1);
      expect(result).toBeErr(Cl.uint(100)); // err-owner-only
    });

    it("should block operations when paused", () => {
      simnet.callPublicFn("WisdomNetcontract", "pause-contract", [], deployer);
      
      const { result } = simnet.callPublicFn("WisdomNetcontract", "create-prediction-market", [
        Cl.stringAscii("Test Market"),
        Cl.stringAscii("Description"),
        Cl.stringAscii("Politics"),
        Cl.stringAscii("https://source.com"),
        Cl.uint(100),
        Cl.uint(50)
      ], address1);
      expect(result).toBeErr(Cl.uint(111)); // err-contract-paused
    });

    it("should allow owner to unpause", () => {
      simnet.callPublicFn("WisdomNetcontract", "pause-contract", [], deployer);
      const { result } = simnet.callPublicFn("WisdomNetcontract", "unpause-contract", [], deployer);
      expect(result).toBeOk(Cl.bool(true));
    });
  });

  describe("Input Validation", () => {
    it("should reject empty title", () => {
      const { result } = simnet.callPublicFn("WisdomNetcontract", "create-prediction-market", [
        Cl.stringAscii(""),
        Cl.stringAscii("Description"),
        Cl.stringAscii("Politics"),
        Cl.stringAscii("https://source.com"),
        Cl.uint(100),
        Cl.uint(50)
      ], address1);
      expect(result).toBeErr(Cl.uint(114)); // err-invalid-input
    });

    it("should reject empty category", () => {
      const { result } = simnet.callPublicFn("WisdomNetcontract", "create-prediction-market", [
        Cl.stringAscii("Test Market"),
        Cl.stringAscii("Description"),
        Cl.stringAscii(""),
        Cl.stringAscii("https://source.com"),
        Cl.uint(100),
        Cl.uint(50)
      ], address1);
      expect(result).toBeErr(Cl.uint(114)); // err-invalid-input
    });

    it("should reject zero prediction duration", () => {
      const { result } = simnet.callPublicFn("WisdomNetcontract", "create-prediction-market", [
        Cl.stringAscii("Test Market"),
        Cl.stringAscii("Description"),
        Cl.stringAscii("Politics"),
        Cl.stringAscii("https://source.com"),
        Cl.uint(0),
        Cl.uint(50)
      ], address1);
      expect(result).toBeErr(Cl.uint(102)); // err-invalid-params
    });
  });

  describe("Rate Limiting", () => {
    it("should allow up to 5 operations per block", () => {
      for (let i = 1; i <= 5; i++) {
        const result = simnet.callPublicFn("WisdomNetcontract", "create-prediction-market", [
          Cl.stringAscii(`Market ${i}`),
          Cl.stringAscii("Description"),
          Cl.stringAscii("Politics"),
          Cl.stringAscii("https://source.com"),
          Cl.uint(100),
          Cl.uint(50)
        ], address1);
        expect(result.result).toBeOk(Cl.uint(i));
      }
    });

    it("should track last operation block", () => {
      simnet.callPublicFn("WisdomNetcontract", "create-prediction-market", [
        Cl.stringAscii("Test Market"),
        Cl.stringAscii("Description"),
        Cl.stringAscii("Politics"),
        Cl.stringAscii("https://source.com"),
        Cl.uint(100),
        Cl.uint(50)
      ], address2);

      const { result } = simnet.callReadOnlyFn("WisdomNetcontract", "get-last-operation-block", [Cl.standardPrincipal(address2)], deployer);
      expect(result).toBeDefined();
    });
  });

  describe("Market Security", () => {
    it("should create market successfully", () => {
      const { result } = simnet.callPublicFn("WisdomNetcontract", "create-prediction-market", [
        Cl.stringAscii("Will BTC reach 100k?"),
        Cl.stringAscii("Bitcoin price prediction"),
        Cl.stringAscii("Crypto"),
        Cl.stringAscii("https://coinmarketcap.com"),
        Cl.uint(1000),
        Cl.uint(500)
      ], address1);
      expect(result).toBeOk(Cl.uint(1));
    });

    it("should prevent placing prediction with zero stake", () => {
      simnet.callPublicFn("WisdomNetcontract", "create-prediction-market", [
        Cl.stringAscii("Test Market"),
        Cl.stringAscii("Description"),
        Cl.stringAscii("Politics"),
        Cl.stringAscii("https://source.com"),
        Cl.uint(1000),
        Cl.uint(500)
      ], address1);

      simnet.mineEmptyBlock();

      const { result } = simnet.callPublicFn("WisdomNetcontract", "place-prediction", [
        Cl.uint(1),
        Cl.bool(true),
        Cl.uint(0)
      ], address2);
      expect(result).toBeErr(Cl.uint(102)); // err-invalid-params
    });
  });

  describe("Decision Security", () => {
    it("should prevent creator from voting on own decision", () => {
      simnet.callPublicFn("WisdomNetcontract", "create-decision", [
        Cl.stringAscii("Should we implement feature X?"),
        Cl.stringAscii("Description of feature X"),
        Cl.stringAscii("Development"),
        Cl.uint(1000),
        Cl.list([])
      ], address1);

      simnet.mineEmptyBlock();

      const { result } = simnet.callPublicFn("WisdomNetcontract", "cast-vote", [
        Cl.uint(1),
        Cl.bool(true)
      ], address1);
      expect(result).toBeErr(Cl.uint(115)); // err-self-interaction
    });

    it("should prevent duplicate votes", () => {
      simnet.callPublicFn("WisdomNetcontract", "create-decision", [
        Cl.stringAscii("Test Decision"),
        Cl.stringAscii("Description"),
        Cl.stringAscii("Development"),
        Cl.uint(1000),
        Cl.list([])
      ], address1);

      simnet.mineEmptyBlock();

      simnet.callPublicFn("WisdomNetcontract", "cast-vote", [
        Cl.uint(1),
        Cl.bool(true)
      ], address2);

      simnet.mineEmptyBlock();

      const { result } = simnet.callPublicFn("WisdomNetcontract", "cast-vote", [
        Cl.uint(1),
        Cl.bool(false)
      ], address2);
      expect(result).toBeErr(Cl.uint(103)); // err-already-exists
    });
  });

  describe("Read-Only Security Functions", () => {
    it("should get market creator", () => {
      simnet.callPublicFn("WisdomNetcontract", "create-prediction-market", [
        Cl.stringAscii("Test Market"),
        Cl.stringAscii("Description"),
        Cl.stringAscii("Politics"),
        Cl.stringAscii("https://source.com"),
        Cl.uint(100),
        Cl.uint(50)
      ], address1);

      const { result } = simnet.callReadOnlyFn("WisdomNetcontract", "get-market-creator", [Cl.uint(1)], deployer);
      expect(result).toBeSome(Cl.standardPrincipal(address1));
    });

    it("should get decision creator", () => {
      simnet.callPublicFn("WisdomNetcontract", "create-decision", [
        Cl.stringAscii("Test Decision"),
        Cl.stringAscii("Description"),
        Cl.stringAscii("Development"),
        Cl.uint(1000),
        Cl.list([])
      ], address2);

      const { result } = simnet.callReadOnlyFn("WisdomNetcontract", "get-decision-creator", [Cl.uint(1)], deployer);
      expect(result).toBeSome(Cl.standardPrincipal(address2));
    });
  });
});
