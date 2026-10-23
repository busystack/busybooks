// Install failure reporting before importing any renderer dependencies. A failed
// static import otherwise prevents reader.js from installing its own handlers.
(() => {
    const query = new URL(window.location.href).searchParams
    const session = query.get('session') ?? 'probe'
    let failed = false
    function failure(error) {
        if (failed) return
        failed = true
        const message = String(error?.message ?? error ?? 'Reader startup failed').slice(0, 4096)
        const event = {type: 'error', session, message}
        const json = JSON.stringify(event)
        if (window.webkit?.messageHandlers?.busybooks) window.webkit.messageHandlers.busybooks.postMessage(json)
        else window.chrome?.webview?.postMessage(json)
        window.busybooksProbe?.(event)
    }
    window.addEventListener('error', event => failure(event.error ?? event.message ?? 'Reader resource failed to load'))
    window.addEventListener('unhandledrejection', event => failure(event.reason))
    const content = document.querySelector('#content')
    content.className = 'loading'
    content.setAttribute('aria-busy', 'true')
    content.textContent = query.get('loading') ?? ''
    import('./reader.js').catch(failure)
})()
