# (C) British Crown Copyright 2015, Met Office
#
# This file is part of mo_pack.
#
# mo_pack is free software: you can redistribute it and/or modify it under
# the terms of the GNU Lesser General Public License as published by the
# Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# mo_pack is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public License
# along with mo_pack. If not, see <http://www.gnu.org/licenses/>.

from __future__ import absolute_import, division, print_function

import numpy as np
cimport numpy as np


#: The WGDOS packing algorithm generally produces smaller data payloads
#: than the unpacked equivalent. However this is not a given, especially
#: for smaller data arrays. With the MINIMUM_WGDOS_PACK_SIZE global we
#: define what the smallest data buffer we are prepared to allocate for packed
#: data to be put into. Even with this safety net, it is assumed there are
#: configurations which will invoke a Seg Fault, in those cases, try setting
#: this even higher.
MINIMUM_WGDOS_PACK_SIZE = 2**8


cdef extern from "logerrors.h":
    ctypedef struct function:
        char name[128]
        function* parent

    void MO_syslog(int value, char* message, const function* const caller)


cdef extern from "wgdosstuff.h":
    long wgdos_unpack(char* packed_data,
                      long unpacked_len,
                      char* unpacked_data,
                      float mdi,
                      function* parent) nogil

    long wgdos_pack(long ncols, long nrows,
                    char* unpacked_data,
                    float mdi, long bacc,
                    char* packed_data,
                    int* packed_length,
                    function* parent) nogil


cdef void MO_syslog(int value, char* message, const function* const caller):
    # A dumb implementation of the system logging - i.e. don't do anything.
    pass

## For debugging purposes, enable the following (and comment out the above).
#from libc.stdio cimport printf
#cdef void MO_syslog(int value, char* message, const function* const caller):
#    printf(message)
#    printf('\n')


def unpack_wgdos(packed_data_buffer, int nrows, int ncols,
                 float missing_data_indicator=-1e30):
    """
    Unpack the given data using WGDOS unpacking.
    """
    cdef np.ndarray[np.float32_t, ndim=2, mode="c"] unpacked_data
    unpacked_data = np.empty([nrows, ncols], dtype=np.float32)

    cdef np.ndarray[np.uint8_t, ndim=1] packed_data
    packed_data = np.frombuffer(packed_data_buffer, dtype=np.uint8)

    cdef long ret_code

    with nogil:
        ret_code = wgdos_unpack(packed_data.data, nrows * ncols,
                                unpacked_data.data, missing_data_indicator,
                                <function*> None)

    if ret_code != 0:
        raise ValueError('WGDOS exit code was non-zero: {}'.format(ret_code))

    return unpacked_data


def pack_wgdos(np.ndarray[np.float32_t, ndim=2] unpacked_data,
               long accuracy=-6,
               float missing_data_indicator=-1e30):
    """Pack the given 2d array with the given accuracy using WGDOS packing."""
    # The x and y size of the input array.
    cdef int d0, d1
    d0, d1 = unpacked_data.shape[0], unpacked_data.shape[1]

    # Allocate an array which can be used by the packing algorithm
    buffer_size = max(d0 * d1, MINIMUM_WGDOS_PACK_SIZE)
    cdef np.ndarray[np.float32_t, mode="c"] packed_data
    packed_data = np.zeros(buffer_size, dtype=np.float32)

    # The length of the packed data. A pointer reference will be passed for the
    # packing algorithm to update.
    cdef int length = -1

    cdef long ret_code
    with nogil:
        ret_code = wgdos_pack(d0, d1, unpacked_data.data,
                              missing_data_indicator, accuracy,
                              packed_data.data, &length,
                              <function*> None)

    if ret_code != 0:
        raise ValueError('WGDOS exit code was non-zero: {}'.format(ret_code))

    # Return the data buffer which is actually of interest.
    return packed_data[:length].data
