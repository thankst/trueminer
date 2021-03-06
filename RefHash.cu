#include <fstream>
#include <iostream>
#include <chrono>

#include "cuda.h"
#include "cuda_runtime.h"
#include "gpu_var.h"
#include "hash.h"
#include "CuAPI_helper.h"


static cudaError_t CuRun(byte input[HEAD_SIZE], byte target1[TARG_SIZE], byte target2[TARG_SIZE])
{
	clock_t start, end;
	float duration, rnonce;
	
	CuDeviceVarManager& varMgr = CuDeviceVarManager::GetInstance();
	void* devPtr = nullptr;
	CuChecker cudaStatus = cudaSuccess;
	const uint64 nonce_start = 0;

	std::cout << std::dec;

	CUDA_GET_SYMBOL_ADDR(devPtr, gTable);
	auto host_gTable = varMgr.AddVar<uint64>("gTable", devPtr, 1048576);

	CUDA_GET_SYMBOL_ADDR(devPtr, kInput);
	auto host_kInput = varMgr.AddVar<byte>("kInput", devPtr, HEAD_SIZE);

	CUDA_GET_SYMBOL_ADDR(devPtr, kTarget1);
	auto host_kTarget1 = varMgr.AddVar<byte>("kTarget1", devPtr, TARG_SIZE);

	CUDA_GET_SYMBOL_ADDR(devPtr, kTarget2);
	auto host_kTarget2 = varMgr.AddVar<byte>("kTarget2", devPtr, TARG_SIZE);

	CUDA_GET_SYMBOL_ADDR(devPtr, gOutput);
	auto host_gOutput = varMgr.AddVar<byte>("gOutput", devPtr, DGST_SIZE);

	CUDA_GET_SYMBOL_ADDR(devPtr, gFoundIdx);
	auto host_gFoundIdx = varMgr.AddVar<uint64>("gFoundIdx", devPtr);

	CUDA_GET_SYMBOL_ADDR(devPtr, kXor);
	auto host_kXor = varMgr.AddVar<int>("kXor", devPtr, 256);

	// Init gpu memory
	varMgr.CopyToGpuArray(host_kInput, input, HEAD_SIZE);
	varMgr.CopyToGpuArray(host_kTarget1, target1, TARG_SIZE);
	varMgr.CopyToGpuArray(host_kTarget2, target2, TARG_SIZE);

	// Init kXor table
	{
		int xor[256];
		for (int i = 0; i < 256; i++)
		{
			int r = 0;
			int val = i;
			for (int j = 0; j < 8 && val; j++)
			{
				r ^= (val & 0x1);
				val = val >> 1;
			}
			xor[i] = r;
		}
		varMgr.CopyToGpuArray<int>(host_kXor, xor, 256);
	}

	// Set device parameters
	// Change deviceIdx to proper device if you have multiple GPUs.
	const int deviceIdx = 0;
	cudaStatus = cudaSetDevice(deviceIdx);

	int smCount = 1;
	cudaStatus = cudaDeviceSetLimit(cudaLimitStackSize, 4 * 1024);
	{
		cudaDeviceProp prop;
		cudaStatus = cudaGetDeviceProperties(&prop, deviceIdx);
		smCount = prop.multiProcessorCount;
		printf("SMCount = %d\n", smCount);
	}

	printf("Start kernel ", smCount);
	start = clock();
	compute << <smCount, 1024 >> > (nonce_start);
	
	cudaStatus = cudaGetLastError();
	cudaStatus = cudaDeviceSynchronize();

	rnonce = (float)varMgr.GetFromGpuSingleVal<uint64>(host_gFoundIdx);
	end = clock();

	duration = ((float)(end - start) / CLOCKS_PER_SEC);
	printf("nonce is found [%f] in [%f]\n", rnonce, duration);
	printf("Hashrate is %f\n", (rnonce - nonce_start) / duration);

	return cudaSuccess;
}

// test function
int main()
{

    byte input[HEAD_SIZE] = {0x18,	0x64,	0xe9,	0xa0,	0x68,	0x3b,	0xa6,	0x8d,	0xb5,	0xec,	0x5c,	0x6c,	0xf1,	0x3b,	0xf3,	0x94,	0xe4,	0x46,	0xbb,	
		0xe7,	0x82,	0x3b,	0xca,	0x36,	0x0a,	0x1f,	0xc5,	0x24,	0x0f,	0x69,	0xf7,	0x13 };
	byte target1[TARG_SIZE] = { 0xff,	0xff,	0xff,	0xff,	0xff,	0xff,	0xff,	0xff,	0xff,	0xff,	0xff,	0xff,	0xff,	0xff,	0x00,	0x00 };
	byte target2[TARG_SIZE] = { 0xff,	0xff,	0xff,	0xff,	0xff,	0xff,	0xff,	0xff,	0xff,	0xff,	0xff,	0xff,	0xff,	0xff,	0x00,	0x00 };
	byte output[DGST_SIZE];

	CuRun(input, target1, target2);

	return 0;
}
