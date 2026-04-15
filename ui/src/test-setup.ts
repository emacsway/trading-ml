/** jsdom polyfills required by lightweight-charts and similar browser libs. */

if (typeof window !== 'undefined') {
  if (!window.matchMedia) {
    Object.defineProperty(window, 'matchMedia', {
      writable: true,
      value: (query: string) => ({
        matches: false,
        media: query,
        onchange: null,
        addListener: () => {},
        removeListener: () => {},
        addEventListener: () => {},
        removeEventListener: () => {},
        dispatchEvent: () => false,
      }),
    });
  }

  if (!('ResizeObserver' in window)) {
    (window as unknown as { ResizeObserver: unknown }).ResizeObserver =
      class {
        observe() {}
        unobserve() {}
        disconnect() {}
      };
  }

  // jsdom canvas getContext returns null — stub the minimum surface that
  // lightweight-charts touches during setData + destroy.
  const proto = (globalThis.HTMLCanvasElement as typeof HTMLCanvasElement | undefined)?.prototype;
  if (proto && !(proto as { __stubbed?: boolean }).__stubbed) {
    (proto as { __stubbed?: boolean }).__stubbed = true;
    const ctxStub = new Proxy({}, {
      get: () => () => undefined,
    });
    (proto as unknown as { getContext: () => unknown }).getContext = () => ctxStub;
  }
}
