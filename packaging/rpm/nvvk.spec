Name:           nvvk
Version:        0.4.1
Release:        1%{?dist}
Summary:        NVIDIA Vulkan Extensions Library for Linux Gaming

License:        MIT
URL:            https://github.com/user/nvvk
Source0:        %{name}-%{version}.tar.gz

BuildRequires:  zig >= 0.16
BuildRequires:  vulkan-headers
BuildRequires:  vulkan-loader-devel

Requires:       vulkan-loader

%description
nvvk provides optimized NVIDIA Vulkan extension wrappers with C ABI exports
for integration with DXVK, vkd3d-proton, and other Vulkan translation layers.

Features:
* VK_NV_low_latency2: NVIDIA Reflex integration for reduced input latency
* Frame generation: AI-based frame interpolation to double effective FPS
* VK_NV_device_diagnostic_checkpoints: GPU crash debugging
* VK_NV_optical_flow: Motion vector extraction
* Full Vulkan 1.4 support with backwards compatibility to 1.3

%package devel
Summary:        Development files for nvvk
Requires:       %{name}%{?_isa} = %{version}-%{release}

%description devel
This package contains the header files needed for developing
applications that use the nvvk library.

%package vulkan-layers
Summary:        NVIDIA Vulkan Layers for frame generation and low latency
Requires:       %{name}%{?_isa} = %{version}-%{release}

%description vulkan-layers
This package provides Vulkan layers for automatic frame generation
and NVIDIA Reflex low latency mode:
* VK_LAYER_NV_frame_generation: AI frame interpolation layer
* VK_LAYER_NV_low_latency: Automatic Reflex marker injection

%prep
%autosetup

%build
zig build -Doptimize=ReleaseFast

%check
zig build test

%install
# Install library
install -D -m 755 zig-out/lib/libnvvk.so \
    %{buildroot}%{_libdir}/libnvvk.so

# Install Vulkan layer libraries
install -D -m 755 zig-out/lib/libnvvk_layer.so \
    %{buildroot}%{_libdir}/libnvvk_layer.so
install -D -m 755 zig-out/lib/libnvvk_layer_ll.so \
    %{buildroot}%{_libdir}/libnvvk_layer_ll.so

# Install layer manifests
install -D -m 644 VK_LAYER_NV_frame_generation.json \
    %{buildroot}%{_datadir}/vulkan/implicit_layer.d/VK_LAYER_NV_frame_generation.json
install -D -m 644 VK_LAYER_NV_low_latency.json \
    %{buildroot}%{_datadir}/vulkan/implicit_layer.d/VK_LAYER_NV_low_latency.json

# Fix library paths in manifests
sed -i 's|./libnvvk_layer.so|%{_libdir}/libnvvk_layer.so|' \
    %{buildroot}%{_datadir}/vulkan/implicit_layer.d/VK_LAYER_NV_frame_generation.json
sed -i 's|./libnvvk_layer_ll.so|%{_libdir}/libnvvk_layer_ll.so|' \
    %{buildroot}%{_datadir}/vulkan/implicit_layer.d/VK_LAYER_NV_low_latency.json

# Install headers
install -D -m 644 zig-out/include/nvvk.h %{buildroot}%{_includedir}/nvvk.h
install -D -m 644 zig-out/include/nvvk_low_latency.h %{buildroot}%{_includedir}/nvvk_low_latency.h
install -D -m 644 zig-out/include/nvvk_diagnostics.h %{buildroot}%{_includedir}/nvvk_diagnostics.h

# Install docs
install -D -m 644 README.md %{buildroot}%{_docdir}/%{name}/README.md
install -D -m 644 TODO.md %{buildroot}%{_docdir}/%{name}/TODO.md

%files
%license LICENSE
%doc README.md TODO.md
%{_libdir}/libnvvk.so

%files devel
%{_includedir}/nvvk.h
%{_includedir}/nvvk_low_latency.h
%{_includedir}/nvvk_diagnostics.h

%files vulkan-layers
%{_libdir}/libnvvk_layer.so
%{_libdir}/libnvvk_layer_ll.so
%{_datadir}/vulkan/implicit_layer.d/VK_LAYER_NV_frame_generation.json
%{_datadir}/vulkan/implicit_layer.d/VK_LAYER_NV_low_latency.json

%changelog
* Mon Jan 20 2026 Your Name <your.email@example.com> - 0.4.1-1
- Full Zig 0.16.0 compatibility
- Vulkan 1.4 support with backwards compatibility
- Add VK_LAYER_NV_frame_generation for automatic frame interpolation
- Add VK_LAYER_NV_low_latency for automatic NVIDIA Reflex
- Add validation layer integration
- Add push descriptor support (Vulkan 1.4 promoted)
- DXVK and vkd3d-proton integration patches
- Async sleep with callback support

* Sun Jan 19 2026 Your Name <your.email@example.com> - 0.4.0-1
- Initial release
