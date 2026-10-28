const { buildPoseidon, buildBabyjub } = require("circomlibjs");

async function main() {
  const poseidon = await buildPoseidon();
  const babyJub = await buildBabyjub();
  const F = babyJub.F;

  const C = BigInt("20938321923713421783834546971150917626109057576724182511814352916423950805931");

  const sk = 123456789n;
  const r = 987654321n;

  const G = babyJub.Base8;
  const PK = babyJub.mulPointEscalar(G, sk);
  const R = babyJub.mulPointEscalar(G, r);

  const Rx = F.toObject(R[0]).toString();
  const Ry = F.toObject(R[1]).toString();
  const PKx = F.toObject(PK[0]).toString();
  const PKy = F.toObject(PK[1]).toString();

  const e = BigInt(F.toObject(poseidon([R[0], R[1], PK[0], PK[1], C])).toString());
  const s = (r + e * sk) % babyJub.subOrder;

  console.log(JSON.stringify({
    Rx,
    Ry,
    PKx,
    PKy,
    C: C.toString(),
    s: s.toString()
  }, null, 2));
}

main().catch(console.error);
