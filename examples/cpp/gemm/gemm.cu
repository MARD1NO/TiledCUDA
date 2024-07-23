#include "util.hpp"

template <typename InType, typename AccType, typename GlobalA, typename RegA,
          typename LoaderA, typename GlobalB, typename RegB, typename LoaderB,
          typename GlobalC, typename RegC, typename CStorer>
__global__ void simple_gemm(const InType* dA, const InType* dB, AccType* dC) {
    GlobalA gA(dA);
    RegA rA;
    LoaderA loader_a;

    GlobalB gB(dB);
    RegB rB;
    LoaderB loader_b;

    RegC acc;

    loader_a(gA, rA);
    loader_b(gB, rB);
    __syncthreads();

    compute::gemm_(rA, rB, acc);

    __syncthreads();

    GlobalC gC(dC);
    CStorer storer_c;
    storer_c(acc, gC);
}

int main() {
    using InType = __half;
    using AccType = float;

    const int kM = 16;
    const int kN = 16;
    const int kK = 16;

    // initialize data
    thrust::host_vector<InType> h_a(kM * kK);
    for (int i = 0; i < h_a.size(); ++i) {
        h_a[i] = static_cast<InType>(rand_float());
    }

    thrust::host_vector<InType> h_b(kK * kN);
    for (int i = 0; i < h_b.size(); ++i) {
        h_b[i] = static_cast<InType>(rand_float());
    }

    thrust::host_vector<AccType> h_c(kM * kN);
    thrust::fill(h_c.begin(), h_c.end(), 0.);

    thrust::device_vector<InType> d_a = h_a;
    thrust::device_vector<InType> d_b = h_b;
    thrust::device_vector<AccType> d_c = h_c;

    const InType* A = thrust::raw_pointer_cast(d_a.data());
    const InType* B = thrust::raw_pointer_cast(d_b.data());
    AccType* C = thrust::raw_pointer_cast(d_c.data());

    using Config = GemmTraits<InType, AccType, GemmShape<kM, kN, kK>>;

    using RegA = typename Config::RegA;
    using RegB = typename Config::RegB;
    using RegC = typename Config::RegC;

    std::cout << "kThreads: " << Config::kThreads << std::endl
              << "RegA: " << RegA{} << std::endl
              << "RegB: " << RegB{} << std::endl
              << "RegC: " << RegC{} << std::endl;

    dim3 dim_grid(1, 1, 1);
    dim3 dim_block(Config::kThreads, 1, 1);

    int size_ab = (kM + kN) * kK * sizeof(InType);
    int size_c = kM * kN * sizeof(AccType);
    int shm_size = size_ab > size_c ? size_ab : size_c;

    simple_gemm<InType, AccType, typename Config::GlobalA, RegA,
                typename Config::ALoader, typename Config::GlobalB, RegB,
                typename Config::BLoader, typename Config::GlobalC,
                typename Config::RegC, typename Config::CStorer>
        <<<dim_grid, dim_block, shm_size>>>(A, B, C);
    h_c = d_c;
    cudaDeviceSynchronize();

    {  // check correctness
        thrust::host_vector<AccType> h_c2(kM * kN);
        thrust::fill(h_c2.begin(), h_c2.end(), 0.);
        naive_gemm(kM, kN, kK, thrust::raw_pointer_cast(h_a.data()),
                   thrust::raw_pointer_cast(h_b.data()), h_c2.data());

        bool passed =
            check_results(thrust::raw_pointer_cast(h_c.data()),
                          thrust::raw_pointer_cast(h_c2.data()), kM * kN);

        if (passed) {
            std::cout << "Test passed." << std::endl;
        } else {
            std::cerr << "Test failed." << std::endl;
        }
    }

    return 0;
}
