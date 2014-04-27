#include <stdio.h>
#include "Consts.h"
#include "cross.h"
#include "Global.h"
#include "LatticeContainer.h"
#include <vector>
#include <algorithm>
#include <iostream>

#ifdef CROSS_CPU

uint3 CpuBlock, CpuThread, CpuSize;

void memcpy2D(void * dst_, int dpitch, void * src_, int spitch, int width, int height) {
	char * dst = (char*) dst_, *src = (char*) src_;
	for (int i=0; i<height; i++) {
		memcpy(dst + i*dpitch, src + i*spitch, width);
	}
}

#else

// Copyright 1993-2010 NVIDIA Corporation.  All rights reserved.
void HandleError( cudaError_t err,
                         const char *file,
                         int line ) {
    if (err != cudaSuccess) {
        fprintf(stderr, "[%d] %s in %s at line %d\n", D_MPI_RANK, cudaGetErrorString( err ),
                file, line );
        exit( EXIT_FAILURE );
    }
}

/*int GetMaxThreads()
{
            cudaFuncAttributes * attr = new cudaFuncAttributes;
            HANDLE_ERROR( cudaFuncGetAttributes(attr, RunKernel<Node>) );
            printf( "Constant mem:%ld\n", attr->constSizeBytes);
            printf( "Local    mem:%ld\n", attr->localSizeBytes);
            printf( "Max  threads:%d\n", attr->maxThreadsPerBlock);
            printf( "Reg   Number:%d\n", attr->numRegs);
            printf( "Shared   mem:%ld\n", attr->sharedSizeBytes);
            return attr->maxThreadsPerBlock;
}
*/

#endif

#ifndef CROSS_SYNCALLOC

        struct ptrpair {
                void ** ptr;
                size_t size;
                ptrpair() { ptr=NULL; size = 0; }
                ptrpair(const ptrpair & p) { ptr=p.ptr; size=p.size; };
                ptrpair(void ** ptr_, size_t size_) { ptr=ptr_; size=size_; };
                inline const bool operator< (const ptrpair & B) const {
                        return size < B.size;
                };
        };

        std::vector< ptrpair > ptrlist;
        std::vector< std::pair< void *, std::vector< ptrpair > > > freelist;

        CudaError cudaPreAlloc(void ** ptr, size_t size) {
                DEBUG1(printf("Preallocation of %d b\n", (int) size);)
                ptrlist.push_back(ptrpair(ptr, size));
        //	return cudaMalloc(ptr, size);
                return CudaSuccess;
        }

        #define MEM_ALIGN 128

        CudaError cudaAllocFinalize() {
                sort(ptrlist.begin(), ptrlist.end());
                ptrpair ptr;
                size_t fullsize=0;
                for (int i = 0; i < ptrlist.size(); i++) {
                        size_t size = ptrlist[i].size;
                        int align = MEM_ALIGN;
                        while (align > size) align /= 2;
                        size = (((size-1)/align)+1)*align;
                        fullsize += size;
                        ptrlist[i].size=size;
                }
                char * tmp;
                if (fullsize > 1e9) {
                        printf("[%d] Cumulative allocation of %d b (%.1f GB)\n", D_MPI_RANK, (int) fullsize, ((float) fullsize)/1e9);
                } else if (fullsize > 1e6) {
                        printf("[%d] Cumulative allocation of %d b (%.1f MB)\n", D_MPI_RANK, (int) fullsize, ((float) fullsize)/1e6);
                } else if (fullsize > 1e3) {
                        printf("[%d] Cumulative allocation of %d b (%.1f kB)\n", D_MPI_RANK, (int) fullsize, ((float) fullsize)/1e3);
                } else {
                        printf("[%d] Cumulative allocation of %d b\n", D_MPI_RANK, (int) fullsize);
                }
                CudaMalloc((void **) &tmp,fullsize);
                if (tmp == NULL) {
                        std::cerr << "FATAL ERROR: Not enaught memory! tried to allocate (cumulatice): " << fullsize << " b\n";
                        exit(-1);
                }
                CudaMemset( tmp, 0, fullsize );
                void * main_ptr = tmp;
                std::vector< ptrpair > tofree;
                while (!ptrlist.empty()) {
                        ptr = ptrlist.back();
                        DEBUG1(printf("[%d] Preallocation gave %d b\n", D_MPI_RANK, (int) ptr.size);)
        //		cudaMalloc(ptr.ptr,ptr.size);
                        *(ptr.ptr) = (void **)tmp;
                        tmp += ptr.size;
                        tofree.push_back(ptr);
                        ptrlist.pop_back();
                }
                freelist.push_back(std::pair< void *, std::vector< ptrpair > > ( main_ptr, tofree));
                return CudaSuccess;
        }


        CudaError cudaAllocFreeAll() {
                std::pair< void *, std::vector< ptrpair > > ptr_list;
                while (!freelist.empty()) {
                        ptr_list = freelist.back();
//                        printf("ptr_list.first = %p\n", ptr_list.first);
                        CudaFree(ptr_list.first);
                        std::vector< ptrpair >::iterator it;
                        for (it=ptr_list.second.begin(); it != ptr_list.second.end(); it++) {
//                                printf(" *((*it).ptr) = %p\n", *((*it).ptr));
                                *((*it).ptr) = NULL;
                        }
                        freelist.pop_back();
                }
                return CudaSuccess;
        }
                                


#else

        CudaError cudaPreAlloc(void ** ptr, size_t size) {
                DEBUG1(printf("Preallocation of %d b\n", (int) size);)
                CudaError ret = CudaMalloc(ptr, size);
                CudaMemset( *ptr, 0, size );
                return ret;
        }

        CudaError cudaAllocFinalize() {
                return CudaSuccess;
        }

#endif

