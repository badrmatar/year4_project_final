// lib/services/kalman_filter.dart
import 'package:vector_math/vector_math.dart';

/// A production-level 2D Kalman filter with a constant velocity model.
/// The state vector is [x, y, vx, vy].
class KalmanFilter2D {
  // State vector: [x, y, vx, vy]
  Vector4 x;

  // Covariance matrix (4x4)
  Matrix4 P;

  // Process noise scaling (tunable parameter)
  final double processNoise;

  // Measurement noise variance (assumed identical for x and y)
  final double measurementNoise;

  /// Constructs the Kalman filter with an initial position and optional initial velocity.
  /// [processNoise] and [measurementNoise] should be tuned for your application.
  KalmanFilter2D({
    required double initialX,
    required double initialY,
    double initialVx = 0,
    double initialVy = 0,
    // Tuned parameters: adjust these based on your environment.
    this.processNoise = 1e-2,
    this.measurementNoise = 5.0,
  })  : x = Vector4(initialX, initialY, initialVx, initialVy),
  // Initialize P as an identity matrix (or adjust as needed)
        P = Matrix4.identity();

  /// Prediction step: propagate the state and covariance forward by [dt] seconds.
  void predict(double dt) {
    // Define the state transition matrix F for a constant velocity model:
    // F = [[1, 0, dt, 0],
    //      [0, 1, 0, dt],
    //      [0, 0, 1,  0],
    //      [0, 0, 0,  1]]
    final F = Matrix4.identity()..setEntry(0, 2, dt)..setEntry(1, 3, dt);

    // Predict state: x = F * x
    x = F.transform(x);

    // Compute the process noise covariance Q.
    // Q = [ [dt^4/4,       0, dt^3/2,       0],
    //       [      0, dt^4/4,       0, dt^3/2],
    //       [dt^3/2,       0,   dt^2,       0],
    //       [      0, dt^3/2,       0,   dt^2] ] * processNoise
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

    // Update covariance: P = F * P * F^T + Q.
    Matrix4 result = F * P * F.transposed; // Use the transposed getter.
    result.add(Q); // Add Q in place.
    P = result;
  }

  /// Measurement update: update the state with a new measurement ([measX], [measY]).
  void update(double measX, double measY) {
    // Measurement vector (position only)
    final z = Vector2(measX, measY);
    // Predicted measurement: H * x, where H extracts the first two components.
    final hx = Vector2(x.x, x.y);
    // Innovation (residual)
    final yInnov = z - hx;

    // Innovation covariance S is the upper left 2x2 block of P plus measurement noise.
    final double S00 = P.entry(0, 0) + measurementNoise;
    final double S01 = P.entry(0, 1);
    final double S10 = P.entry(1, 0);
    final double S11 = P.entry(1, 1) + measurementNoise;

    // Invert the 2x2 innovation covariance matrix S.
    final double det = S00 * S11 - S01 * S10;
    if (det == 0) {
      // Handle singular matrix appropriately.
      return;
    }
    final double invS00 = S11 / det;
    final double invS01 = -S01 / det;
    final double invS10 = -S10 / det;
    final double invS11 = S00 / det;

    // Compute the Kalman Gain K.
    final List<double> K0 = List.generate(
      4,
          (i) => P.entry(i, 0) * invS00 + P.entry(i, 1) * invS10,
    );
    final List<double> K1 = List.generate(
      4,
          (i) => P.entry(i, 0) * invS01 + P.entry(i, 1) * invS11,
    );

    // Update the state vector: x = x + K * innovation.
    x[0] += K0[0] * yInnov.x + K1[0] * yInnov.y;
    x[1] += K0[1] * yInnov.x + K1[1] * yInnov.y;
    x[2] += K0[2] * yInnov.x + K1[2] * yInnov.y;
    x[3] += K0[3] * yInnov.x + K1[3] * yInnov.y;

    // Update covariance: P = (I - K*H) * P.
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
