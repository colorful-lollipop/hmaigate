export interface ApiProblem {
  status: number;
  code: string;
  message: string;
}

class ApiClient {
  private authorization = '';
  private readonly baseUrl = import.meta.env.VITE_API_BASE_URL ?? 'http://localhost:8088/api/v1';

  authenticate(username: string, password: string): void {
    this.authorization = `Basic ${window.btoa(`${username}:${password}`)}`;
  }

  clearAuthentication(): void {
    this.authorization = '';
  }

  async request<T>(path: string, init: RequestInit = {}): Promise<T> {
    const headers = new Headers(init.headers);
    headers.set('Accept', 'application/json');
    if (init.body !== undefined) {
      headers.set('Content-Type', 'application/json');
    }
    if (this.authorization) {
      headers.set('Authorization', this.authorization);
    }
    const response = await fetch(`${this.baseUrl}${path}`, { ...init, headers });
    if (!response.ok) {
      let problem: ApiProblem = { status: response.status, code: 'request_failed', message: `请求失败 (${response.status})` };
      try {
        problem = await response.json() as ApiProblem;
      } catch {
        // Non-JSON responses are still represented by the HTTP status above.
      }
      throw new Error(problem.message);
    }
    if (response.status === 204 || response.status === 202) {
      return undefined as T;
    }
    return response.json() as Promise<T>;
  }

  get<T>(path: string): Promise<T> {
    return this.request<T>(path);
  }

  post<T>(path: string, body?: unknown): Promise<T> {
    return this.request<T>(path, { method: 'POST', body: body === undefined ? undefined : JSON.stringify(body) });
  }

  put<T>(path: string, body: unknown): Promise<T> {
    return this.request<T>(path, { method: 'PUT', body: JSON.stringify(body) });
  }
}

export const api = new ApiClient();
