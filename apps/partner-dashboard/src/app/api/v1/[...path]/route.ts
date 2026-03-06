import { NextRequest, NextResponse } from 'next/server';
import { API_URL } from '@/lib/config';
import { ACCESS_TOKEN_COOKIE } from '@/lib/auth';

async function proxyRequest(request: NextRequest, pathParts: string[]) {
  const url = new URL(request.url);
  const targetUrl = `${API_URL}/api/v1/${pathParts.join('/')}${url.search}`;

  const headers = new Headers(request.headers);
  headers.delete('host');

  const accessToken = request.cookies.get(ACCESS_TOKEN_COOKIE)?.value;
  if (accessToken) {
    headers.set('Authorization', `Bearer ${accessToken}`);
  }

  const method = request.method.toUpperCase();
  const body =
    method === 'GET' || method === 'HEAD' ? undefined : await request.arrayBuffer();

  try {
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), 30000);

    const response = await fetch(targetUrl, {
      method,
      headers,
      body,
      signal: controller.signal,
    });

    clearTimeout(timeoutId);

    const responseHeaders = new Headers(response.headers);
    return new NextResponse(await response.arrayBuffer(), {
      status: response.status,
      headers: responseHeaders,
    });
  } catch (error) {
    if (error instanceof DOMException && error.name === 'AbortError') {
      return NextResponse.json(
        { error: 'Request timed out', message: 'The backend server took too long to respond.' },
        { status: 504 }
      );
    }
    return NextResponse.json(
      { error: 'Service unavailable', message: 'Unable to connect to the backend server.' },
      { status: 502 }
    );
  }
}

export async function GET(
  request: NextRequest,
  { params }: { params: { path: string[] } }
) {
  return proxyRequest(request, params.path);
}

export async function POST(
  request: NextRequest,
  { params }: { params: { path: string[] } }
) {
  return proxyRequest(request, params.path);
}

export async function PUT(
  request: NextRequest,
  { params }: { params: { path: string[] } }
) {
  return proxyRequest(request, params.path);
}

export async function PATCH(
  request: NextRequest,
  { params }: { params: { path: string[] } }
) {
  return proxyRequest(request, params.path);
}

export async function DELETE(
  request: NextRequest,
  { params }: { params: { path: string[] } }
) {
  return proxyRequest(request, params.path);
}
