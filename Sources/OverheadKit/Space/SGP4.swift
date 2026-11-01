import Foundation

struct Vec3: Equatable, Sendable {
    var x: Double, y: Double, z: Double

    var length: Double { (x * x + y * y + z * z).squareRoot() }
    var unit: Vec3 { let l = length; return Vec3(x: x / l, y: y / l, z: z / l) }

    func dot(_ o: Vec3) -> Double { x * o.x + y * o.y + z * o.z }
    static func + (a: Vec3, b: Vec3) -> Vec3 { Vec3(x: a.x + b.x, y: a.y + b.y, z: a.z + b.z) }
    static func - (a: Vec3, b: Vec3) -> Vec3 { Vec3(x: a.x - b.x, y: a.y - b.y, z: a.z - b.z) }
    static func * (a: Vec3, k: Double) -> Vec3 { Vec3(x: a.x * k, y: a.y * k, z: a.z * k) }
}

/// The SGP4 orbit propagator for near-Earth satellites (orbital period under 225 minutes), as published in Spacetrack
/// Report #3 and revised by Vallado, Crawford, Hujsak and Kelso (2006). It turns a two-line element set into a position
/// and velocity in the TEME frame at any time near the epoch. Deep-space satellites need extra terms and are refused.
struct SGP4: Sendable {
    // WGS-72 constants, which two-line element sets are fitted with.
    private static let earthRadiusKm = 6378.135
    private static let mu = 398_600.8
    private static let xke = 60.0 / (earthRadiusKm * earthRadiusKm * earthRadiusKm / mu).squareRoot()
    private static let j2 = 0.001082616
    private static let j3 = -0.00000253881
    private static let j4 = -0.00000165597
    private static let j3oj2 = j3 / j2
    private static let twoPi = 2 * Double.pi
    private static let x2o3 = 2.0 / 3.0

    private let epochDate: Date
    private let bstar, ecco, inclo, nodeo, argpo, mo: Double
    private let noUnkozai: Double
    private var isSimple = false
    private var aycof = 0.0, con41 = 0.0, cc1 = 0.0, cc4 = 0.0, cc5 = 0.0, d2 = 0.0, d3 = 0.0, d4 = 0.0
    private var delmo = 0.0, eta = 0.0, argpdot = 0.0, omgcof = 0.0, sinmao = 0.0, t2cof = 0.0, t3cof = 0.0, t4cof = 0.0, t5cof = 0.0
    private var x1mth2 = 0.0, x7thm1 = 0.0, mdot = 0.0, nodedot = 0.0, xlcof = 0.0, xmcof = 0.0, nodecf = 0.0

    /// Nil for orbits SGP4 cannot model: deep-space periods, or elements that make no physical sense.
    init?(_ elements: OrbitalElements) {
        let re = Self.earthRadiusKm, xke = Self.xke, j2 = Self.j2, j3oj2 = Self.j3oj2, x2o3 = Self.x2o3
        epochDate = elements.epoch
        bstar = elements.bstar; ecco = elements.eccentricity; inclo = elements.inclinationRad
        nodeo = elements.raanRad; argpo = elements.argumentOfPerigeeRad; mo = elements.meanAnomalyRad
        let noKozai = elements.meanMotion
        guard ecco >= 0, ecco < 1, noKozai > 0 else { return nil }

        // Recover the original mean motion and semi-major axis from the Kozai mean motion in the element set.
        let eccsq = ecco * ecco, omeosq = 1 - eccsq, rteosq = omeosq.squareRoot()
        let cosio = cos(inclo), cosio2 = cosio * cosio
        let ak = pow(xke / noKozai, x2o3)
        let d1 = 0.75 * j2 * (3 * cosio2 - 1) / (rteosq * omeosq)
        var del = d1 / (ak * ak)
        let adel = ak * (1 - del * del - del * (1.0 / 3.0 + 134 * del * del / 81))
        del = d1 / (adel * adel)
        noUnkozai = noKozai / (1 + del)
        guard 2 * Double.pi / noUnkozai < 225 else { return nil }

        let ao = pow(xke / noUnkozai, x2o3)
        let sinio = sin(inclo)
        let po = ao * omeosq
        let con42 = 1 - 5 * cosio2
        con41 = -con42 - cosio2 - cosio2
        let posq = po * po
        let rp = ao * (1 - ecco)
        isSimple = rp < (220.0 / re + 1)

        var sfour = 78.0 / re + 1
        var qzms2t = pow((120.0 - 78.0) / re, 4)
        let perige = (rp - 1) * re
        if perige < 156 {
            sfour = perige - 78
            if perige < 98 { sfour = 20 }
            qzms2t = pow((120 - sfour) / re, 4)
            sfour = sfour / re + 1
        }
        let pinvsq = 1 / posq
        let tsi = 1 / (ao - sfour)
        eta = ao * ecco * tsi
        let etasq = eta * eta, eeta = ecco * eta
        let psisq = abs(1 - etasq)
        let coef = qzms2t * pow(tsi, 4)
        let coef1 = coef / pow(psisq, 3.5)
        let cc2 = coef1 * noUnkozai * (ao * (1 + 1.5 * etasq + eeta * (4 + etasq))
                                       + 0.375 * j2 * tsi / psisq * con41 * (8 + 3 * etasq * (8 + etasq)))
        cc1 = bstar * cc2
        var cc3 = 0.0
        if ecco > 1e-4 { cc3 = -2 * coef * tsi * j3oj2 * noUnkozai * sinio / ecco }
        x1mth2 = 1 - cosio2
        cc4 = 2 * noUnkozai * coef1 * ao * omeosq * (eta * (2 + 0.5 * etasq) + ecco * (0.5 + 2 * etasq)
            - j2 * tsi / (ao * psisq) * (-3 * con41 * (1 - 2 * eeta + etasq * (1.5 - 0.5 * eeta))
                                         + 0.75 * x1mth2 * (2 * etasq - eeta * (1 + etasq)) * cos(2 * argpo)))
        cc5 = 2 * coef1 * ao * omeosq * (1 + 2.75 * (etasq + eeta) + eeta * etasq)
        let cosio4 = cosio2 * cosio2
        let temp1 = 1.5 * j2 * pinvsq * noUnkozai
        let temp2 = 0.5 * temp1 * j2 * pinvsq
        let temp3 = -0.46875 * Self.j4 * pinvsq * pinvsq * noUnkozai
        mdot = noUnkozai + 0.5 * temp1 * rteosq * con41 + 0.0625 * temp2 * rteosq * (13 - 78 * cosio2 + 137 * cosio4)
        argpdot = -0.5 * temp1 * con42 + 0.0625 * temp2 * (7 - 114 * cosio2 + 395 * cosio4) + temp3 * (3 - 36 * cosio2 + 49 * cosio4)
        let xhdot1 = -temp1 * cosio
        nodedot = xhdot1 + (0.5 * temp2 * (4 - 19 * cosio2) + 2 * temp3 * (3 - 7 * cosio2)) * cosio
        omgcof = bstar * cc3 * cos(argpo)
        xmcof = ecco > 1e-4 ? -x2o3 * coef * bstar / eeta : 0
        nodecf = 3.5 * omeosq * xhdot1 * cc1
        t2cof = 1.5 * cc1
        let divisor = abs(cosio + 1) > 1.5e-12 ? 1 + cosio : 1.5e-12
        xlcof = -0.25 * j3oj2 * sinio * (3 + 5 * cosio) / divisor
        aycof = -0.5 * j3oj2 * sinio
        delmo = pow(1 + eta * cos(mo), 3)
        sinmao = sin(mo)
        x7thm1 = 7 * cosio2 - 1

        if !isSimple {
            let cc1sq = cc1 * cc1
            d2 = 4 * ao * tsi * cc1sq
            let temp = d2 * tsi * cc1 / 3
            d3 = (17 * ao + sfour) * temp
            d4 = 0.5 * temp * ao * tsi * (221 * ao + 31 * sfour) * cc1
            t3cof = d2 + 2 * cc1sq
            t4cof = 0.25 * (3 * d3 + cc1 * (12 * d2 + 10 * cc1sq))
            t5cof = 0.2 * (3 * d4 + 12 * cc1 * d3 + 6 * d2 * d2 + 15 * cc1sq * (2 * d2 + cc1sq))
        }
    }

    /// Position (km) and velocity (km/s) in the TEME frame, `date` being any time; nil if the orbit has decayed or the model fails.
    func propagate(at date: Date) -> (position: Vec3, velocity: Vec3)? {
        propagate(minutesSinceEpoch: date.timeIntervalSince(epochDate) / 60)
    }

    func propagate(minutesSinceEpoch t: Double) -> (position: Vec3, velocity: Vec3)? {
        let re = Self.earthRadiusKm, xke = Self.xke, j2 = Self.j2, twoPi = Self.twoPi, x2o3 = Self.x2o3
        let vkmpersec = re * xke / 60

        // Secular gravity and atmospheric drag.
        let xmdf = mo + mdot * t
        let argpdf = argpo + argpdot * t
        let nodedf = nodeo + nodedot * t
        var argpm = argpdf, mm = xmdf
        let t2 = t * t
        var nodem = nodedf + nodecf * t2
        var tempa = 1 - cc1 * t
        var tempe = bstar * cc4 * t
        var templ = t2cof * t2
        if !isSimple {
            let delomg = omgcof * t
            let delm = xmcof * (pow(1 + eta * cos(xmdf), 3) - delmo)
            let temp = delomg + delm
            mm = xmdf + temp
            argpm = argpdf - temp
            let t3 = t2 * t, t4 = t3 * t
            tempa = tempa - d2 * t2 - d3 * t3 - d4 * t4
            tempe += bstar * cc5 * (sin(mm) - sinmao)
            templ += t3cof * t3 + t4 * (t4cof + t * t5cof)
        }
        var nm = noUnkozai
        var em = ecco
        guard nm > 0 else { return nil }
        let am = pow(xke / nm, x2o3) * tempa * tempa
        nm = xke / pow(am, 1.5)
        em -= tempe
        guard em < 1, em >= -0.001 else { return nil }
        if em < 1e-6 { em = 1e-6 }
        mm += noUnkozai * templ
        var xlm = mm + argpm + nodem
        nodem = nodem.truncatingRemainder(dividingBy: twoPi)
        argpm = argpm.truncatingRemainder(dividingBy: twoPi)
        xlm = xlm.truncatingRemainder(dividingBy: twoPi)
        mm = (xlm - argpm - nodem).truncatingRemainder(dividingBy: twoPi)

        let sinip = sin(inclo), cosip = cos(inclo)
        let ep = em, argpp = argpm, nodep = nodem, mp = mm

        // Long-period periodics.
        let axnl = ep * cos(argpp)
        var temp = 1 / (am * (1 - ep * ep))
        let aynl = ep * sin(argpp) + temp * aycof
        let xl = mp + argpp + nodep + temp * xlcof * axnl

        // Kepler's equation.
        let u = (xl - nodep).truncatingRemainder(dividingBy: twoPi)
        var eo1 = u, tem5 = 9999.9, sineo1 = 0.0, coseo1 = 0.0
        var iterations = 1
        while abs(tem5) >= 1e-12 && iterations <= 10 {
            sineo1 = sin(eo1); coseo1 = cos(eo1)
            tem5 = 1 - coseo1 * axnl - sineo1 * aynl
            tem5 = (u - aynl * coseo1 + axnl * sineo1 - eo1) / tem5
            if abs(tem5) >= 0.95 { tem5 = tem5 > 0 ? 0.95 : -0.95 }
            eo1 += tem5
            iterations += 1
        }

        // Short-period preliminary quantities.
        let ecose = axnl * coseo1 + aynl * sineo1
        let esine = axnl * sineo1 - aynl * coseo1
        let el2 = axnl * axnl + aynl * aynl
        let pl = am * (1 - el2)
        guard pl >= 0 else { return nil }
        let rl = am * (1 - ecose)
        let rdotl = am.squareRoot() * esine / rl
        let rvdotl = pl.squareRoot() / rl
        let betal = (1 - el2).squareRoot()
        temp = esine / (1 + betal)
        let sinu = am / rl * (sineo1 - aynl - axnl * temp)
        let cosu = am / rl * (coseo1 - axnl + aynl * temp)
        var su = atan2(sinu, cosu)
        let sin2u = (cosu + cosu) * sinu
        let cos2u = 1 - 2 * sinu * sinu
        temp = 1 / pl
        let temp1 = 0.5 * j2 * temp
        let temp2 = temp1 * temp

        let mrt = rl * (1 - 1.5 * temp2 * betal * con41) + 0.5 * temp1 * x1mth2 * cos2u
        su -= 0.25 * temp2 * x7thm1 * sin2u
        let xnode = nodep + 1.5 * temp2 * cosip * sin2u
        let xinc = inclo + 1.5 * temp2 * cosip * sinip * cos2u
        let mvt = rdotl - nm * temp1 * x1mth2 * sin2u / xke
        let rvdot = rvdotl + nm * temp1 * (x1mth2 * cos2u + 1.5 * con41) / xke
        guard mrt >= 1 else { return nil }

        // Orientation vectors.
        let sinsu = sin(su), cossu = cos(su), snod = sin(xnode), cnod = cos(xnode), sini = sin(xinc), cosi = cos(xinc)
        let xmx = -snod * cosi, xmy = cnod * cosi
        let ux = xmx * sinsu + cnod * cossu, uy = xmy * sinsu + snod * cossu, uz = sini * sinsu
        let vx = xmx * cossu - cnod * sinsu, vy = xmy * cossu - snod * sinsu, vz = sini * cossu

        let r = mrt * re
        return (Vec3(x: r * ux, y: r * uy, z: r * uz),
                Vec3(x: (mvt * ux + rvdot * vx) * vkmpersec, y: (mvt * uy + rvdot * vy) * vkmpersec, z: (mvt * uz + rvdot * vz) * vkmpersec))
    }
}
