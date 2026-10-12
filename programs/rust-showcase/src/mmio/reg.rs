use core::{cell::UnsafeCell, mem::MaybeUninit};

#[repr(C, align(4))]
pub struct R32<T = u32>(UnsafeCell<T>);

unsafe impl<T: Sync> Sync for R32<T> {}

impl<T> R32<T> {
    #[inline(always)]
    pub fn read(&self) -> T {
        const { assert!(core::mem::size_of::<T>() == 4) }
        unsafe { self.0.get().read_volatile() }
    }
}

#[repr(C, align(4))]
pub struct W32<T = u32>(UnsafeCell<T>);

unsafe impl<T: Sync> Sync for W32<T> {}

impl<T> W32<T> {
    #[inline(always)]
    pub fn write(&self, value: T) {
        const { assert!(core::mem::size_of::<T>() == 4) }
        unsafe { self.0.get().write_volatile(value) }
    }
}

#[repr(C, align(4))]
pub struct Pad32(MaybeUninit<u32>);
