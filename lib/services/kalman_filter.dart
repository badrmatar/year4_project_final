import 'package:vector_math/vector_math.dart';

class KalmanFilter2D {

  Vector4 x;

  Matrix4 P;

  final double processNoise;

  final double measurementNoise;

  KalmanFilter2D({
    required double initialX,
    required double initialY,
    double initialVx = 0,
    double initialVy = 0,

    this.processNoise = 1e-2,
    this.measurementNoise = 5.0,
  })  : x = Vector4(initialX, initialY, initialVx, initialVy),

        P = Matrix4.identity();

  void predict(double dt) {

    final F = Matrix4.identity()..setEntry(0, 2, dt)..setEntry(1, 3, dt);

    x = F.transform(x);

    final double dt2 = dt * dt;
    final double dt3 = dt2 * dt;
    final double dt4 = dt3 * dt;

    final Q = Matrix4.zero()
      ..setEntry(0, 0, dt4 / 4 * processNoise)
      ..setEntry(0, 2, dt3 / 2 * processNoise)
      ..setEntry(1, 1, dt4 / 4 * processNoise)
      ..setEntry(1, 3, dt3 / 2 * processNoise)
      ..setEntry(2, 0, dt3 / 2 * processNoise)
      ..setEntry(2, 2, dt2 * processNoise)
      ..setEntry(3, 1, dt3 / 2 * processNoise)
      ..setEntry(3, 3, dt2 * processNoise);

    Matrix4 result = F * P * F.transposed;
    result.add(Q);
    P = result;
  }

  void update(double measX, double measY) {

    final z = Vector2(measX, measY);

    final hx = Vector2(x.x, x.y);

    final yInnov = z - hx;

    final double S00 = P.entry(0, 0) + measurementNoise;
    final double S01 = P.entry(0, 1);
    final double S10 = P.entry(1, 0);
    final double S11 = P.entry(1, 1) + measurementNoise;

    final double det = S00 * S11 - S01 * S10;
    if (det == 0) {

      return;
    }
    final double invS00 = S11 / det;
    final double invS01 = -S01 / det;
    final double invS10 = -S10 / det;
    final double invS11 = S00 / det;

    final List<double> K0 = List.generate(
      4,
          (i) => P.entry(i, 0) * invS00 + P.entry(i, 1) * invS10,
    );
    final List<double> K1 = List.generate(
      4,
          (i) => P.entry(i, 0) * invS01 + P.entry(i, 1) * invS11,
    );

    x[0] += K0[0] * yInnov.x + K1[0] * yInnov.y;
    x[1] += K0[1] * yInnov.x + K1[1] * yInnov.y;
    x[2] += K0[2] * yInnov.x + K1[2] * yInnov.y;
    x[3] += K0[3] * yInnov.x + K1[3] * yInnov.y;

    final Matrix4 newP = Matrix4.zero();
    for (int i = 0; i < 4; i++) {
      for (int j = 0; j < 4; j++) {
        newP.setEntry(i, j,
            P.entry(i, j) - (K0[i] * P.entry(0, j) + K1[i] * P.entry(1, j)));
      }
    }
    P = newP;
  }
}