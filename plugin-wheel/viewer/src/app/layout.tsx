import type { Metadata } from 'next'
import '@/styles/viewer.css'

export const metadata: Metadata = {
  title: 'Wheel View',
  description: 'Workflow inspection viewer',
}

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <head>
        <script src="https://cdn.jsdelivr.net/npm/mermaid@10.9.0/dist/mermaid.min.js" />
      </head>
      <body>
        <div id="viewer-root">{children}</div>
        <script dangerouslySetInnerHTML={{ __html: `mermaid.initialize({ startOnLoad: false, theme: 'dark' })` }} />
      </body>
    </html>
  )
}
