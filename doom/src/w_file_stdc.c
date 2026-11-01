//
// Copyright(C) 1993-1996 Id Software, Inc.
// Copyright(C) 2005-2014 Simon Howard
//
// This program is free software; you can redistribute it and/or
// modify it under the terms of the GNU General Public License
// as published by the Free Software Foundation; either version 2
// of the License, or (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// DESCRIPTION:
//	WAD I/O functions.
//

#include <stdio.h>

#include "m_misc.h"
#include "w_file.h"
#include "z_zone.h"

typedef struct
{
    wad_file_t wad;
    FILE *fstream;
} stdc_wad_file_t;

extern wad_file_class_t stdc_wad_file;

/* RV32 testbench port: direct RAM-backed file access (see fsys_rv32.c) */
#include <stdint.h>
extern int fs_open(const char *name);
extern unsigned fs_length(int fd);
extern int fs_readat(int fd, unsigned off, void *dst, unsigned len);
extern int fs_close(int fd);

static wad_file_t *W_StdC_OpenFile(char *path)
{
    stdc_wad_file_t *result;
    int fd;

    fd = fs_open(path);

    if (fd < 0)
    {
        return NULL;
    }

    // Create a new stdc_wad_file_t to hold the file handle.

    result = Z_Malloc(sizeof(stdc_wad_file_t), PU_STATIC, 0);
    result->wad.file_class = &stdc_wad_file;
    result->wad.mapped = NULL;
    result->fstream = (FILE *)(uintptr_t)fd;
    result->wad.length = fs_length(fd);

    return &result->wad;
}

static void W_StdC_CloseFile(wad_file_t *wad)
{
    stdc_wad_file_t *stdc_wad;

    stdc_wad = (stdc_wad_file_t *) wad;

    fs_close((int)(uintptr_t)stdc_wad->fstream);
    Z_Free(stdc_wad);
}

size_t W_StdC_Read(wad_file_t *wad, unsigned int offset,
                   void *buffer, size_t buffer_len)
{
    stdc_wad_file_t *stdc_wad;

    stdc_wad = (stdc_wad_file_t *) wad;

    return (size_t)fs_readat((int)(uintptr_t)stdc_wad->fstream,
                             offset, buffer, (unsigned)buffer_len);
}


wad_file_class_t stdc_wad_file = 
{
    W_StdC_OpenFile,
    W_StdC_CloseFile,
    W_StdC_Read,
};


