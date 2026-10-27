// Install failure reporting before importing any renderer dependencies. A failed
// static import otherwise prevents reader.js from installing its own handlers.
(() => {
    const query = new URL(window.location.href).searchParams
    const session = query.get('session') ?? 'probe'
    let failed = false
    function report(type, details) {
        const event = {type, session, ...details}
        const json = JSON.stringify(event)
        if (window.webkit?.messageHandlers?.busybooks) window.webkit.messageHandlers.busybooks.postMessage(json)
        else window.chrome?.webview?.postMessage(json)
        window.busybooksProbe?.(event)
    }
    function failure(error) {
        if (failed) return
        failed = true
        const message = String(error?.message ?? error ?? 'Reader startup failed').slice(0, 4096)
        report('error', {message})
    }
    window.addEventListener('error', event => {
        // https://www.w3.org/TR/resize-observer/#deliver-resize-error
        // Resize Observer's specified notification defers remaining observations
        // to another rendering update. Keep it diagnostic; an actual exception,
        // rejected promise or resource failure must still fail the reader.
        if (event.isTrusted === true && event.error == null && (event.filename === '' || event.filename === window.location.href) && event.lineno === 0 && event.colno === 0 &&
            event.message === 'ResizeObserver loop completed with undelivered notifications.') {
            report('diagnostic', {stage: 'resize-observer', message: event.message})
            return
        }
        failure(event.error ?? event.message ?? 'Reader resource failed to load')
    })
    window.addEventListener('unhandledrejection', event => failure(event.reason))
    const content = document.querySelector('#content')
    content.className = 'loading'
    content.setAttribute('aria-busy', 'true')
    content.textContent = query.get('loading') ?? ''
    import('./reader.js').catch(failure)
})()
