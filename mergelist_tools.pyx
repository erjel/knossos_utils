cimport cython
import numpy as np
cimport numpy as np
from cython.operator cimport dereference
from libcpp.string cimport string
from libcpp.utility cimport pair
from libcpp.unordered_map cimport unordered_map
from libcpp.unordered_set cimport unordered_set

def subobject_map_from_mergelist(mergelist_content):
    """
    Extracts a single object layer from a mergelist and returns a map of subobject ID > object ID.
    If one subobject is contained in more than one object, the last object is kept.
    :param mergelist_content:
        the mergelist content as a string
    """
    cdef unordered_map[np.uint64_t, np.uint64_t] subobjects_map
    for line in mergelist_content.split("\n")[0::4]:
        elems = line.split()
        if len(elems) > 0:
            object_id = elems[0]
            for subobject_id in elems[3:]:
                subobjects_map[np.uint64(subobject_id)] = np.uint64(object_id)
    return subobjects_map

@cython.boundscheck(False)
def apply_mergelist(np.ndarray[np.uint64_t, ndim=3] segmentation, mergelist_content, np.uint64_t pad=0):
    """
    Merges subobjects using a dictionary of (subobject, object) pairs. So each subobject can only be member of one object.
    The resulting segmentation for each merged group contains only the first ID of that group
    :param segmentation:
        3D array containing the subobject IDs
    :param mergelist_content:
        the mergelist content as a string
    :param pad:
        optional padding that is excluded from mergelist application
    """
    cdef unordered_map[np.uint64_t, np.uint64_t] subobject_map = subobject_map_from_mergelist(mergelist_content)
    cdef int width = segmentation.shape[0]
    cdef int height = segmentation.shape[1]
    cdef int depth = segmentation.shape[2]
    cdef Py_ssize_t x, y, z
    cdef np.uint64_t subobject_id
    cdef np.uint64_t object_id
    cdef np.uint64_t new_subobject_id

    cdef unordered_map[np.uint64_t, np.uint64_t] object_map

    for z in xrange(pad, depth - pad):
        for y in xrange(pad, height - pad):
            for x in xrange(pad, width - pad):
                subobject_id = segmentation[x, y, z]
                object_id = subobject_map[subobject_id]
                new_subobject_id = subobject_id
                object_map_it = object_map.find(object_id)

                if object_map_it != object_map.end():
                    new_subobject_id =  dereference(object_map_it).second
                else:
                    object_map[object_id] = subobject_id

                segmentation[x, y, z] = new_subobject_id

    return segmentation

@cython.boundscheck(False)
def generate_mergelist(np.ndarray[np.uint64_t, ndim=3] segmentation, np.uint64_t background_id=0, np.uint64_t pad=0, np.ndarray[np.uint64_t, ndim=1] offsets=np.array([0, 0, 0])):
    """
    Generates a mergelist from a segmentation in which each subobject is contained in its own object.
    The object's coordinate is the first coordinate of the subobject.
    :param segmentation:
        3D array containing the subobject IDs
    :background_id:
        The background id will be skipped
    :pad:
        optional padding that is excluded from mergelist generation
    :offsets:
        the voxel coordinate closest to 0, 0, 0 of the whole dataset, used to give objects their correct coordinate
    """
    cdef int width = segmentation.shape[0]
    cdef int height = segmentation.shape[1]
    cdef int depth = segmentation.shape[2]
    cdef Py_ssize_t x, y, z
    cdef np.uint64_t next_id
    cdef np.uint64_t so_cache = background_id

    cdef unordered_set[np.uint64_t] seen_subobjects
    new_mergelist = ""
    for z in xrange(pad, depth - pad):
        for y in xrange(pad, height - pad):
            for x in xrange(pad, width - pad):
                next_id = segmentation[x, y, z]
                if next_id == background_id or next_id == so_cache or seen_subobjects.find(next_id) != seen_subobjects.end():
                    continue
                so_cache = next_id
                seen_subobjects.insert(next_id)
                new_mergelist += "{0} 0 0 {0}\n{1} {2} {3}\n\n\n".format(next_id, offsets[0]+x, offsets[1]+y, offsets[2]+z)
    return new_mergelist