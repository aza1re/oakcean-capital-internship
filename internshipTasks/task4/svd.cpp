#include <iostream>
#include <vector>
#include <random>
#include <cmath>
#include <chrono>
#include <iomanip>

using std::vector;
using namespace std;

// compute y = A * x  (A is m x n, row-major)
static vector<double> matvec(int m, int n, const vector<double>& A, const vector<double>& x) {
    vector<double> y(m, 0.0);
    for (int i = 0; i < m; ++i) {
        double s = 0.0;
        int row = i * n;
        for (int j = 0; j < n; ++j) s += A[row + j] * x[j];
        y[i] = s;
    }
    return y;
}

// compute y = A^T * x  (A is m x n, row-major)
static vector<double> matTvec(int m, int n, const vector<double>& A, const vector<double>& x) {
    vector<double> y(n, 0.0);
    for (int j = 0; j < n; ++j) {
        double s = 0.0;
        for (int i = 0; i < m; ++i) s += A[i * n + j] * x[i];
        y[j] = s;
    }
    return y;
}

static double norm(const vector<double>& v) {
    double s = 0.0;
    for (double x : v) s += x * x;
    return std::sqrt(s);
}

static void normalize(vector<double>& v) {
    double n = norm(v);
    if (n == 0.0) return;
    for (double &x : v) x /= n;
}

// Power-method-based dominant SVD (returns sigma, fills u and v)
double power_svd(int m, int n, const vector<double>& A, vector<double>& u, vector<double>& v,
                 int max_iters = 1000, double tol = 1e-9) {
    // initialize v with random values
    std::mt19937_64 rng((unsigned)std::chrono::high_resolution_clock::now().time_since_epoch().count());
    std::uniform_real_distribution<double> dist(-1.0, 1.0);
    v.assign(n, 0.0);
    for (int i = 0; i < n; ++i) v[i] = dist(rng);
    normalize(v);

    double sigma = 0.0;
    for (int iter = 0; iter < max_iters; ++iter) {
        // Av
        vector<double> Av = matvec(m, n, A, v);
        double sigma_new = norm(Av);
        if (sigma_new == 0.0) {
            // zero matrix or v landed in nullspace
            u.assign(m, 0.0);
            v.assign(n, 0.0);
            sigma = 0.0;
            break;
        }
        // u = Av / sigma_new
        u = Av;
        for (double &x : u) x /= sigma_new;

        // v_next = A^T u
        vector<double> v_next = matTvec(m, n, A, u);
        double vnorm = norm(v_next);
        if (vnorm == 0.0) {
            // numerical issue
            break;
        }
        for (double &x : v_next) x /= vnorm;

        // estimate sigma as ||A * v_next|| (v_next normalized)
        vector<double> Av_check = matvec(m, n, A, v_next);
        double sigma_check = norm(Av_check);

        // convergence check on sigma
        if (std::abs(sigma_check - sigma) < tol * std::max(1.0, sigma_check)) {
            v = v_next;
            sigma = sigma_check;
            break;
        }

        v = v_next;
        sigma = sigma_check;
    }

    // final u = A * v / sigma
    if (sigma > 0.0) {
        vector<double> Av_final = matvec(m, n, A, v);
        u = Av_final;
        for (double &x : u) x /= sigma;
    } else {
        u.assign(m, 0.0);
    }
    return sigma;
}

int main() {
    // Example small matrix (m x n) to demonstrate:
    // A = [ 3 1 1
    //       1 3 1 ]
    int m = 2, n = 3;
    vector<double> A = {
        3.0, 1.0, 1.0,
        1.0, 3.0, 1.0
    };

    vector<double> u, v;
    auto t0 = std::chrono::high_resolution_clock::now();
    double sigma = power_svd(m, n, A, u, v, 1000, 1e-10);
    auto t1 = std::chrono::high_resolution_clock::now();

    std::cout << std::fixed << std::setprecision(10);
    std::cout << "Dominant singular value (sigma): " << sigma << "\n\n";
    std::cout << "Left singular vector u (size " << m << "):\n";
    for (double x : u) std::cout << x << "\n";
    std::cout << "\nRight singular vector v (size " << n << "):\n";
    for (double x : v) std::cout << x << "\n";

    auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(t1 - t0).count();
    std::cout << "\nElapsed: " << ms << " ms\n";
    return 0;
}