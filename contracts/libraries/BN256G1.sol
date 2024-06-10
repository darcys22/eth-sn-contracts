// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

library BN256G1 {
    uint256 internal constant FIELD_MODULUS = 0x30644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd47;

    struct G1Point {
        uint X;
        uint Y;
    }

    /// @return the generator of G1
    function P1() internal pure returns (G1Point memory) {
        return G1Point(1, 2);
    }

    function modPow(uint256 base, uint256 exponent, uint256 modulus) internal view returns (uint256) {
        uint256[6] memory input = [32, 32, 32, base, exponent, modulus];
        uint256[1] memory result;
        assembly {
            if iszero(staticcall(sub(gas(), 2000), 5, input, 0xc0, result, 0x20)) {
                revert(0, 0)
            }
        }
        return result[0];
    }

    /// @return r the negation of p, i.e. p.add(p.negate()) should be zero.
    function negate(G1Point memory p) internal pure returns (G1Point memory r) {
        if (p.X == 0 && p.Y == 0) return G1Point(0, 0);
        return G1Point(p.X, FIELD_MODULUS - (p.Y % FIELD_MODULUS));
    }

    /// @return r the sum of two points of G1
    function add(G1Point memory p1, G1Point memory p2) internal view returns (G1Point memory r) {
        uint[4] memory input;
        input[0] = p1.X;
        input[1] = p1.Y;
        input[2] = p2.X;
        input[3] = p2.Y;
        bool success;
        assembly {
            success := staticcall(sub(gas(), 2000), 6, input, 0x80, r, 0x40)
        }
        require(success, "Call to precompiled contract for add failed");
    }

    /// @return r the product of a point on G1 and a scalar, i.e.
    /// p == p.mul(1) and p.add(p) == p.mul(2) for all points p.
    function mul(G1Point memory p, uint s) internal view returns (G1Point memory r) {
        uint[3] memory input;
        input[0] = p.X;
        input[1] = p.Y;
        input[2] = s;
        bool success;
        assembly {
            success := staticcall(sub(gas(), 2000), 7, input, 0x60, r, 0x40)
        }
        require(success, "Call to precompiled contract for mul failed");
    }

    function hashToG1(uint256 h) internal view returns (G1Point memory) {
        return mul(P1(), h);
    }

    function getKeyForG1Point(G1Point memory point) internal pure returns (bytes memory) {
        return abi.encode(point);
    }
}
