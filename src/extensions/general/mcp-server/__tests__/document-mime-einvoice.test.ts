/**
 * An agent hands in a received e-invoice as the XML it arrived as (Peppol BIS Billing 3 / UBL, or CII).
 * Measured 2026-11-20 against the hosted Accounted with SFTI's Swedish example invoices: every one was
 * refused ("Unsupported file type: text/xml"), so a voucher booked on it carried no verifikation. The
 * document service already shape-checks XML; only the MCP door's own list refused it.
 */
import { describe, it, expect } from 'vitest'
import { resolveMcpDocumentMimeType } from '../server'

describe('resolveMcpDocumentMimeType', () => {
  it('takes a received e-invoice as XML, by its type or by its extension', () => {
    expect(resolveMcpDocumentMimeType('faktura.xml', 'text/xml')).toBe('text/xml')
    expect(resolveMcpDocumentMimeType('faktura.xml', 'application/xml')).toBe('application/xml')
    expect(resolveMcpDocumentMimeType('BIS_Billing_30-Resor_Taxi.xml', undefined)).toBe('application/xml')
  })

  it('still refuses what is not a document', () => {
    expect(() => resolveMcpDocumentMimeType('x.exe', 'application/x-msdownload')).toThrow(/Unsupported file type/)
    expect(() => resolveMcpDocumentMimeType('x.zip', undefined)).toThrow(/Cannot infer MIME type/)
  })

  it('keeps the formats it took before', () => {
    expect(resolveMcpDocumentMimeType('kvitto.pdf', undefined)).toBe('application/pdf')
    expect(resolveMcpDocumentMimeType('kvitto.jpg', undefined)).toBe('image/jpeg')
  })
})
