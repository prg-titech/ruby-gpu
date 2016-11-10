#include <stdio.h>

#include <helper_cuda.h>
#include <helper_cuda_gl.h>

using namespace std;


/* ----- BEGIN Shared Library Export ----- */
// taken from http://stackoverflow.com/questions/2164827/explicitly-exporting-shared-library-functions-in-linux

#if defined(_MSC_VER)
    //  Microsoft 
    #define EXPORT __declspec(dllexport)
    #define IMPORT __declspec(dllimport)
#elif defined(_GCC)
    //  GCC
    #define EXPORT __attribute__((visibility("default")))
    #define IMPORT
#else
    //  do nothing and hope for the best?
    #define EXPORT
    #define IMPORT
    #pragma warning Unknown dynamic link import/export semantics.
#endif
/* ----- END Shared Library Export ----- */

/* ----- BEGIN Class Type ----- */
typedef int obj_id_t;
typedef int class_id_t;
/* ----- END Class Type ----- */

/* ----- BEGIN Union Type ----- */
typedef union union_type_value {
    obj_id_t object_id;
    int int_;
    float float_;
    bool bool_;
} union_v_t;

typedef struct union_type_struct
{
    class_id_t class_id;
    union_v_t value;
} union_t;
/* ----- END Union Type ----- */


/* ----- BEGIN Environment (lexical variables) ----- */
// environment_struct must be defined later
typedef struct environment_struct environment_t;
/* ----- END Environment (lexical variables) ----- */

struct environment_struct
{
    int * b1j_base;
    int b1j_size;
    int * b1_base;
    int b1_size;
};


__device__ int block(environment_t *_env_, int value, int index)
{
    // TODO: Your implementation here
    // Image resolution is 1024x683 pixels
    return value;
}


__global__ void kernel(environment_t *_env_, int *_result_)
{
    int t_id = threadIdx.x + blockIdx.x * blockDim.x;

    if (t_id < 699392)
    {
        _result_[t_id] = block(_env_, _env_->b1_base[t_id], t_id);
    }
}


extern "C" EXPORT int *launch_kernel(environment_t *host_env)
{
    /* Modify host environment to contain device pointers addresses */
    
    void * temp_ptr_b1_base = host_env->b1_base;
    checkCudaErrors(cudaMalloc((void **) &host_env->b1_base, 2797568));
    checkCudaErrors(cudaMemcpy(host_env->b1_base, temp_ptr_b1_base, 2797568, cudaMemcpyHostToDevice));


    /* Allocate device environment and copy over struct */
    environment_t *dev_env;
    checkCudaErrors(cudaMalloc(&dev_env, sizeof(environment_t)));
    checkCudaErrors(cudaMemcpy(dev_env, host_env, sizeof(environment_t), cudaMemcpyHostToDevice));

    int *host_result = (int *) malloc(sizeof(int) * 699392);
    int *device_result;
    checkCudaErrors(cudaMalloc(&device_result, sizeof(int) * 699392));
    
    dim3 dim_grid(2732, 1, 1);
    dim3 dim_block(256, 1, 1);

    for (int i = 0; i < 100; i++) {
        kernel<<<dim_grid, dim_block>>>(dev_env, device_result);
    }

    checkCudaErrors(cudaThreadSynchronize());

    checkCudaErrors(cudaMemcpy(host_result, device_result, sizeof(int) * 699392, cudaMemcpyDeviceToHost));
    checkCudaErrors(cudaFree(dev_env));

    return host_result;
}
