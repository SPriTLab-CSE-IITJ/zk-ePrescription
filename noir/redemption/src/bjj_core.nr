// ==========================================================
// BabyJubJub Core
//
// Minimal elliptic-curve implementation for the UltraHonk
// e-Prescription prototype.
//
// Phase 4B – Milestone 2A
// Coordinate Types
// ==========================================================

// ----------------------------------------------------------
// BabyJubJub Parameters
// ----------------------------------------------------------

global CURVE_A: Field = 168700;
global CURVE_D: Field = 168696;

global BASE8_X: Field =
    5299619240641551281634865583518297030282874472190772894086521144482721001553;

global BASE8_Y: Field =
    16950150798460657717958625567821834550301663161624707787222815936182638968203;

pub global SUBORDER: Field =
    2736030358979909402780800718157159386076813972158567259200215660948447373041;
// ----------------------------------------------------------
// Affine Point
// ----------------------------------------------------------

pub struct Point {
    pub x: Field,
    pub y: Field,
}

// ----------------------------------------------------------
// Extended Twisted Edwards Point
// ----------------------------------------------------------

pub struct GroupPoint {
    pub x: Field,
    pub y: Field,
    pub t: Field,
    pub z: Field,
}

// ----------------------------------------------------------
// Curve Parameters
// ----------------------------------------------------------

pub struct Curve {
    pub a: Field,
    pub d: Field,
}

// ----------------------------------------------------------
// Affine Point Implementation
// ----------------------------------------------------------

impl Point {

    /// Construct a point.
    pub fn new(
        x: Field,
        y: Field,
    ) -> Self {

        Self { x, y }
    }

    /// Neutral element.
    pub fn zero() -> Self {

        Self {
            x: 0,
            y: 1,
        }
    }

    /// Returns true if this is the neutral element.
    pub fn is_zero(self) -> bool {

        (self.x == 0)
        &
        (self.y == 1)
    }

    /// Equality test.
    pub fn equals(
        self,
        other: Self,
    ) -> bool {

        (self.x == other.x)
        &
        (self.y == other.y)
    }

    /// Point negation.
    ///
    /// -(x,y) = (-x,y)
    pub fn negate(self) -> Self {

        Self {
            x: -self.x,
            y: self.y,
        }
    }

    /// Convert affine coordinates into
    /// extended Twisted Edwards coordinates.
    pub fn into_group(self) -> GroupPoint {

        GroupPoint::new(
            self.x,
            self.y,
            self.x * self.y,
            1,
        )
    }
}

// ----------------------------------------------------------
// Extended Point Implementation
// ----------------------------------------------------------

impl GroupPoint {

    /// Construct an extended-coordinate point.
    pub fn new(
        x: Field,
        y: Field,
        t: Field,
        z: Field,
    ) -> Self {

        Self {
            x,
            y,
            t,
            z,
        }
    }

    /// Neutral element.
    pub fn zero() -> Self {

        Self {
            x: 0,
            y: 1,
            t: 0,
            z: 1,
        }
    }

    /// Returns true if this is the neutral element.
    pub fn is_zero(self) -> bool {

        (self.x == 0)
        &
        (self.y == self.z)
        &
        (self.y != 0)
        &
        (self.t == 0)
    }

    /// Point negation.
    pub fn negate(self) -> Self {

        Self {
            x: -self.x,
            y: self.y,
            t: -self.t,
            z: self.z,
        }
    }

    /// Convert back into affine coordinates.
    pub fn into_affine(self) -> Point {

        Point::new(
            self.x / self.z,
            self.y / self.z,
        )
    }
}

// ----------------------------------------------------------
// Curve Implementation
// ----------------------------------------------------------

impl Curve {

    /// Construct BabyJubJub curve.
    pub fn new() -> Self {

        Self {
            a: CURVE_A,
            d: CURVE_D,
        }
    }

    /// Returns the BabyJubJub subgroup generator (B8).
    pub fn generator() -> Point {

        Point::new(
            BASE8_X,
            BASE8_Y,
        )
    }

    /// Checks whether a point lies on the curve.
    ///
    /// a*x² + y² = 1 + d*x²*y²
    pub fn contains(
        self,
        p: Point,
    ) -> bool {

        let x2 = p.x * p.x;
        let y2 = p.y * p.y;

        let left =
            self.a * x2 +
            y2;

        let right =
            1 +
            self.d * x2 * y2;

        left == right
    }

    // ======================================================
    // ======================================================


pub fn add(
    self,
    p1: GroupPoint,
    p2: GroupPoint,
) -> GroupPoint {

    let a = p1.x * p2.x;
    let b = p1.y * p2.y;
    let c = self.d * p1.t * p2.t;
    let d = p1.z * p2.z;

    let e =
        (p1.x + p1.y)
        *
        (p2.x + p2.y)
        - a
        - b;

    let f = d - c;
    let g = d + c;
    let h = b - self.a * a;

    let x = e * f;
    let y = g * h;
    let t = e * h;
    let z = f * g;

    GroupPoint::new(
        x,
        y,
        t,
        z,
    )
}




pub fn double(
    self,
    p: GroupPoint,
) -> GroupPoint {

    let a = p.x * p.x;
    let b = p.y * p.y;
    let c = 2 * p.z * p.z;
    let d = self.a * a;

    let e =
        (p.x + p.y)
        *
        (p.x + p.y)
        - a
        - b;

    let g = d + b;
    let f = g - c;
    let h = d - b;

    let x = e * f;
    let y = g * h;
    let t = e * h;
    let z = f * g;

    GroupPoint::new(
        x,
        y,
        t,
        z,
    )
}

pub fn bit_mul<let N: u32>(
    self,
    bits: [bool; N],
    p: GroupPoint,
) -> GroupPoint {

    let mut out = GroupPoint::zero();

    for i in 0..N {

        out = self.add(
            self.double(out),

            if bits[N - i - 1] {
                p
            } else {
                GroupPoint::zero()
            }
        );
    }

    out
}

pub fn scalar_mul(
    self,
    p: GroupPoint,
    scalar: Field,
) -> GroupPoint {

    let bits: [bool; 254] = scalar.to_le_bits::<254>();

    self.bit_mul(bits, p)
}

}
