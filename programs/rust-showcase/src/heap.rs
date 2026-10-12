use core::alloc::{GlobalAlloc, Layout};
use core::cell::UnsafeCell;

use linked_list_allocator::Heap;

#[global_allocator]
static HEAP: SingleCoreHeap = SingleCoreHeap::empty();

struct SingleCoreHeap {
    heap: UnsafeCell<Heap>,
}

unsafe impl Sync for SingleCoreHeap {}

impl SingleCoreHeap {
    pub const fn empty() -> Self {
        Self {
            heap: UnsafeCell::new(Heap::empty()),
        }
    }

    unsafe fn init(&self, start: *mut u8, size: usize) {
        unsafe {
            (*self.heap.get()).init(start, size);
        }
    }

    fn used(&self) -> usize {
        unsafe { (*self.heap.get()).used() }
    }

    fn free(&self) -> usize {
        unsafe { (*self.heap.get()).free() }
    }
}

unsafe impl GlobalAlloc for SingleCoreHeap {
    unsafe fn alloc(&self, layout: Layout) -> *mut u8 {
        unsafe {
            (*self.heap.get())
                .allocate_first_fit(layout)
                .ok()
                .map_or(core::ptr::null_mut(), |allocation| allocation.as_ptr())
        }
    }

    unsafe fn dealloc(&self, ptr: *mut u8, layout: Layout) {
        unsafe {
            (*self.heap.get()).deallocate(core::ptr::NonNull::new_unchecked(ptr), layout);
        }
    }
}

unsafe extern "C" {
    static start_heap: u8;
    static end_heap: u8;
}

/// Initialize the global heap allocator from the linker-provided heap region.
///
/// # Safety
///
/// This must be called exactly once before any allocation happens.
pub unsafe fn init() {
    let start = &raw const start_heap as usize;
    let end = &raw const end_heap as usize;
    let size = end - start;

    unsafe {
        HEAP.init(start as *mut u8, size);
    }
}

pub fn used() -> usize {
    HEAP.used()
}

pub fn free() -> usize {
    HEAP.free()
}
