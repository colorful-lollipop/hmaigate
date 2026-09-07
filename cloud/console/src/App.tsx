import { FormEvent, useCallback, useEffect, useState } from 'react';
import {
  Activity,
  Archive,
  CheckCircle2,
  ChevronRight,
  Clipboard,
  CloudCog,
  Cpu,
  FileLock2,
  KeyRound,
  LayoutDashboard,
  LoaderCircle,
  LogOut,
  MonitorCog,
  Pencil,
  Plus,
  RefreshCw,
  Save,
  Server,
  Settings2,
  ShieldCheck,
  Upload,
  X
} from 'lucide-react';
import { api } from './api';
import {
  Channel,
  DEFAULT_CHANNEL_CONFIGURATION,
  DEFAULT_PROVIDER_CONFIGURATION,
  IssuedDevice,
  ManagedDevice,
  Overview,
  Provider,
  SecurityPolicy
} from './types';

type View = 'overview' | 'channels' | 'providers' | 'policy' | 'devices';

interface ChannelPayload {
  code: string;
  displayName: string;
  clientType: string;
  protocol: string;
  iconKey: string;
  documentationUrl?: string;
  localConfigPathHint?: string;
  enabled: boolean;
  configuration: Record<string, unknown>;
}

interface ProviderPayload {
  code: string;
  displayName: string;
  channelCode: string;
  category: string;
  websiteUrl?: string;
  apiKeyUrl?: string;
  iconKey: string;
  iconColor?: string;
  partner: boolean;
  enabled: boolean;
  configuration: Record<string, unknown>;
}

const navItems = [
  { id: 'overview' as const, label: '运营概览', icon: LayoutDashboard },
  { id: 'channels' as const, label: '渠道', icon: MonitorCog },
  { id: 'providers' as const, label: '供应商预设', icon: Server },
  { id: 'policy' as const, label: '安全策略', icon: ShieldCheck },
  { id: 'devices' as const, label: '设备访问', icon: KeyRound }
];

const emptyOverview: Overview = {
  configVersion: 0,
  publishedChannels: 0,
  publishedProviders: 0,
  activeDevices: 0,
  eventsLast24Hours: 0,
  blockedLast24Hours: 0,
  recentEvents: []
};

export default function App(): JSX.Element {
  const [authenticated, setAuthenticated] = useState(false);
  const [view, setView] = useState<View>('overview');
  const [overview, setOverview] = useState<Overview>(emptyOverview);
  const [channels, setChannels] = useState<Channel[]>([]);
  const [providers, setProviders] = useState<Provider[]>([]);
  const [policy, setPolicy] = useState<SecurityPolicy | null>(null);
  const [devices, setDevices] = useState<ManagedDevice[]>([]);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [notice, setNotice] = useState('');
  const [issued, setIssued] = useState<IssuedDevice | null>(null);

  const refresh = useCallback(async () => {
    setBusy(true);
    setError('');
    try {
      const [nextOverview, nextChannels, nextProviders, nextPolicy, nextDevices] = await Promise.all([
        api.get<Overview>('/admin/overview'),
        api.get<Channel[]>('/admin/channels'),
        api.get<Provider[]>('/admin/providers'),
        api.get<SecurityPolicy>('/admin/security-policy'),
        api.get<ManagedDevice[]>('/admin/devices')
      ]);
      setOverview(nextOverview);
      setChannels(nextChannels);
      setProviders(nextProviders);
      setPolicy(nextPolicy);
      setDevices(nextDevices);
    } catch (requestError) {
      setError(messageOf(requestError));
      throw requestError;
    } finally {
      setBusy(false);
    }
  }, []);

  const signIn = async (username: string, password: string): Promise<void> => {
    api.authenticate(username, password);
    try {
      await refresh();
      setAuthenticated(true);
    } catch {
      api.clearAuthentication();
    }
  };

  const run = async (action: () => Promise<unknown>, success: string): Promise<void> => {
    setNotice('');
    setError('');
    setBusy(true);
    try {
      await action();
      await refresh();
      setNotice(success);
    } catch (requestError) {
      setError(messageOf(requestError));
    } finally {
      setBusy(false);
    }
  };

  if (!authenticated) {
    return <LoginScreen onSignIn={signIn} />;
  }

  return (
    <div className="app-shell">
      <aside className="sidebar">
        <div className="brand">
          <span className="brand-mark"><ShieldCheck size={22} aria-hidden="true" /></span>
          <span>AIGate</span>
        </div>
        <nav aria-label="控制台导航">
          {navItems.map((item) => {
            const Icon = item.icon;
            return (
              <button className={`nav-item ${view === item.id ? 'active' : ''}`} key={item.id} onClick={() => setView(item.id)}>
                <Icon size={18} aria-hidden="true" />
                <span>{item.label}</span>
                {view === item.id && <ChevronRight size={16} className="nav-chevron" aria-hidden="true" />}
              </button>
            );
          })}
        </nav>
        <div className="sidebar-footer">
          <span className="config-version">配置 v{overview.configVersion}</span>
          <button className="nav-item sign-out" title="退出登录" onClick={() => { api.clearAuthentication(); setAuthenticated(false); }}>
            <LogOut size={18} aria-hidden="true" />
            <span>退出登录</span>
          </button>
        </div>
      </aside>

      <main className="workspace">
        <header className="topbar">
          <div>
            <p className="eyebrow">运营控制面</p>
            <h1>{navItems.find((item) => item.id === view)?.label}</h1>
          </div>
          <button className="icon-button" title="刷新全部数据" onClick={() => { void refresh(); }} disabled={busy}>
            <RefreshCw size={19} className={busy ? 'spin' : ''} aria-hidden="true" />
          </button>
        </header>

        {error && <div className="alert alert-error"><X size={18} aria-hidden="true" /><span>{error}</span></div>}
        {notice && <div className="alert alert-success"><CheckCircle2 size={18} aria-hidden="true" /><span>{notice}</span></div>}

        {view === 'overview' && <OverviewPanel overview={overview} />}
        {view === 'channels' && (
          <ChannelPanel
            channels={channels}
            busy={busy}
            onSave={(payload, id) => run(
              () => id ? api.put<Channel>(`/admin/channels/${id}`, payload) : api.post<Channel>('/admin/channels', payload),
              id ? '渠道草稿已保存' : '渠道已创建为草稿'
            )}
            onPublish={(id) => run(() => api.post<Channel>(`/admin/channels/${id}/publish`), '渠道已发布')}
            onArchive={(id) => run(() => api.post<Channel>(`/admin/channels/${id}/archive`), '渠道已下线')}
          />
        )}
        {view === 'providers' && (
          <ProviderPanel
            providers={providers}
            channels={channels}
            busy={busy}
            onSave={(payload, id) => run(
              () => id ? api.put<Provider>(`/admin/providers/${id}`, payload) : api.post<Provider>('/admin/providers', payload),
              id ? '供应商草稿已保存' : '供应商已创建为草稿'
            )}
            onPublish={(id) => run(() => api.post<Provider>(`/admin/providers/${id}/publish`), '供应商已发布')}
            onArchive={(id) => run(() => api.post<Provider>(`/admin/providers/${id}/archive`), '供应商已下线')}
          />
        )}
        {view === 'policy' && policy && (
          <PolicyPanel
            policy={policy}
            busy={busy}
            onSave={(nextPolicy) => run(() => api.put<SecurityPolicy>('/admin/security-policy', { policy: nextPolicy }), '安全策略草稿已保存')}
            onPublish={() => run(() => api.post<SecurityPolicy>('/admin/security-policy/publish'), '安全策略已发布')}
          />
        )}
        {view === 'devices' && (
          <DevicePanel
            devices={devices}
            busy={busy}
            onIssue={(name) => run(async () => {
              const next = await api.post<IssuedDevice>('/admin/devices', { displayName: name });
              setIssued(next);
            }, '设备密钥已签发')}
            onRotate={(id) => run(async () => {
              const next = await api.post<IssuedDevice>(`/admin/devices/${id}/rotate-key`);
              setIssued(next);
            }, '设备密钥已轮换')}
            onRevoke={(id) => run(() => api.post<ManagedDevice>(`/admin/devices/${id}/revoke`), '设备已撤销')}
          />
        )}
      </main>
      {issued && <DeviceKeyDialog issued={issued} onClose={() => setIssued(null)} />}
    </div>
  );
}

function LoginScreen({ onSignIn }: { onSignIn: (username: string, password: string) => Promise<void> }): JSX.Element {
  const [username, setUsername] = useState('admin');
  const [password, setPassword] = useState('');
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);

  const submit = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    setLoading(true);
    setError('');
    try {
      await onSignIn(username, password);
    } catch (requestError) {
      setError(messageOf(requestError));
    } finally {
      setLoading(false);
    }
  };

  return (
    <main className="login-page">
      <form className="login-form" onSubmit={(event) => { void submit(event); }}>
        <div className="login-mark"><ShieldCheck size={30} aria-hidden="true" /></div>
        <h1>AIGate 控制台</h1>
        <p>运营帐号登录</p>
        {error && <div className="form-error">{error}</div>}
        <label>帐号<input value={username} autoComplete="username" onChange={(event) => setUsername(event.target.value)} /></label>
        <label>密码<input type="password" value={password} autoComplete="current-password" onChange={(event) => setPassword(event.target.value)} /></label>
        <button className="primary-button" type="submit" disabled={loading}>
          {loading ? <LoaderCircle className="spin" size={18} aria-hidden="true" /> : <LogOut size={18} aria-hidden="true" />}
          登录
        </button>
      </form>
    </main>
  );
}

function OverviewPanel({ overview }: { overview: Overview }): JSX.Element {
  const stats = [
    { label: '已发布渠道', value: overview.publishedChannels, icon: MonitorCog, tone: 'green' },
    { label: '已发布供应商', value: overview.publishedProviders, icon: Server, tone: 'blue' },
    { label: '活跃设备', value: overview.activeDevices, icon: Cpu, tone: 'amber' },
    { label: '24 小时拦截', value: overview.blockedLast24Hours, icon: FileLock2, tone: 'red' }
  ];
  return (
    <section className="content-stack">
      <div className="stat-grid">
        {stats.map((stat) => {
          const Icon = stat.icon;
          return <article className="stat-card" key={stat.label}>
            <span className={`stat-icon ${stat.tone}`}><Icon size={20} aria-hidden="true" /></span>
            <span className="stat-label">{stat.label}</span>
            <strong>{stat.value}</strong>
          </article>;
        })}
      </div>
      <section className="data-panel">
        <div className="section-heading">
          <div><h2>最近安全与运行事件</h2><span>近 24 小时共 {overview.eventsLast24Hours} 条事件</span></div>
          <Activity size={20} aria-hidden="true" />
        </div>
        <EventTable events={overview.recentEvents} />
      </section>
    </section>
  );
}

function ChannelPanel({ channels, busy, onSave, onPublish, onArchive }: {
  channels: Channel[];
  busy: boolean;
  onSave: (payload: ChannelPayload, id?: string) => Promise<void>;
  onPublish: (id: string) => Promise<void>;
  onArchive: (id: string) => Promise<void>;
}): JSX.Element {
  const [selectedId, setSelectedId] = useState<string | null>(channels[0]?.id ?? null);
  const selected = channels.find((channel) => channel.id === selectedId) ?? null;
  return (
    <section className="split-tool">
      <div className="data-panel list-panel">
        <div className="section-heading"><div><h2>渠道目录</h2><span>{channels.length} 条记录</span></div><button className="icon-button" title="新建渠道" onClick={() => setSelectedId(null)}><Plus size={19} /></button></div>
        <div className="resource-list">
          {channels.map((channel) => <button key={channel.id} className={`resource-row ${selected?.id === channel.id ? 'selected' : ''}`} onClick={() => setSelectedId(channel.id)}>
            <span className="row-glyph"><MonitorCog size={18} /></span><span className="row-content"><strong>{channel.displayName}</strong><small>{channel.code} · {channel.protocol}</small></span><StateBadge state={channel.state} />
          </button>)}
          {channels.length === 0 && <EmptyState icon={<MonitorCog size={24} />} label="尚未创建渠道" />}
        </div>
      </div>
      <ChannelEditor channel={selected} busy={busy} onSave={onSave} onPublish={onPublish} onArchive={onArchive} />
    </section>
  );
}

function ChannelEditor({ channel, busy, onSave, onPublish, onArchive }: {
  channel: Channel | null;
  busy: boolean;
  onSave: (payload: ChannelPayload, id?: string) => Promise<void>;
  onPublish: (id: string) => Promise<void>;
  onArchive: (id: string) => Promise<void>;
}): JSX.Element {
  const [form, setForm] = useState(channelForm(channel));
  const [error, setError] = useState('');
  useEffect(() => { setForm(channelForm(channel)); setError(''); }, [channel]);
  const save = async () => {
    try {
      setError('');
      await onSave({ ...form, documentationUrl: blank(form.documentationUrl), configuration: parseObject(form.configurationText) }, channel?.id);
    } catch (requestError) { setError(messageOf(requestError)); }
  };
  return <section className="editor-panel">
    <EditorHeading title={channel ? '编辑渠道草稿' : '新建渠道'} state={channel?.state} />
    {error && <div className="form-error">{error}</div>}
    <div className="form-grid">
      <label>显示名称<input value={form.displayName} onChange={(event) => setForm({ ...form, displayName: event.target.value })} /></label>
      <label>渠道编码<input value={form.code} disabled={Boolean(channel)} onChange={(event) => setForm({ ...form, code: slug(event.target.value) })} /></label>
      <label>客户端类型<input value={form.clientType} onChange={(event) => setForm({ ...form, clientType: slug(event.target.value) })} /></label>
      <label>协议<input value={form.protocol} onChange={(event) => setForm({ ...form, protocol: slug(event.target.value) })} /></label>
      <label>图标键<input value={form.iconKey} onChange={(event) => setForm({ ...form, iconKey: slug(event.target.value) })} /></label>
      <label>文档 URL<input value={form.documentationUrl} onChange={(event) => setForm({ ...form, documentationUrl: event.target.value })} /></label>
      <label>本地配置文件提示<input value={form.localConfigPathHint} placeholder="~/.claude/settings.json" onChange={(event) => setForm({ ...form, localConfigPathHint: event.target.value })} /></label>
    </div>
    <label className="toggle-row"><input type="checkbox" checked={form.enabled} onChange={(event) => setForm({ ...form, enabled: event.target.checked })} /><span>向设备下发此渠道</span></label>
    <label className="json-field">渠道配置 JSON<textarea value={form.configurationText} onChange={(event) => setForm({ ...form, configurationText: event.target.value })} spellCheck={false} /></label>
    <div className="editor-actions">
      <button className="primary-button" onClick={() => { void save(); }} disabled={busy}><Save size={18} />保存草稿</button>
      {channel && channel.state !== 'ARCHIVED' && <button className="secondary-button" onClick={() => { void onPublish(channel.id); }} disabled={busy}><Upload size={18} />发布</button>}
      {channel && channel.state !== 'ARCHIVED' && <button className="danger-button" onClick={() => { if (window.confirm('下线该渠道后，设备将不再拉取它。')) { void onArchive(channel.id); } }} disabled={busy}><Archive size={18} />下线</button>}
    </div>
  </section>;
}

function ProviderPanel({ providers, channels, busy, onSave, onPublish, onArchive }: {
  providers: Provider[];
  channels: Channel[];
  busy: boolean;
  onSave: (payload: ProviderPayload, id?: string) => Promise<void>;
  onPublish: (id: string) => Promise<void>;
  onArchive: (id: string) => Promise<void>;
}): JSX.Element {
  const [selectedId, setSelectedId] = useState<string | null>(providers[0]?.id ?? null);
  const selected = providers.find((provider) => provider.id === selectedId) ?? null;
  return <section className="split-tool">
    <div className="data-panel list-panel">
      <div className="section-heading"><div><h2>供应商预设</h2><span>{providers.length} 条记录</span></div><button className="icon-button" title="新建供应商" onClick={() => setSelectedId(null)}><Plus size={19} /></button></div>
      <div className="resource-list">
        {providers.map((provider) => <button key={provider.id} className={`resource-row ${selected?.id === provider.id ? 'selected' : ''}`} onClick={() => setSelectedId(provider.id)}>
          <span className="row-glyph provider"><Server size={18} /></span><span className="row-content"><strong>{provider.displayName}</strong><small>{provider.channelCode} · {provider.category}</small></span><StateBadge state={provider.state} />
        </button>)}
        {providers.length === 0 && <EmptyState icon={<Server size={24} />} label="尚未创建供应商" />}
      </div>
    </div>
    <ProviderEditor provider={selected} channels={channels} busy={busy} onSave={onSave} onPublish={onPublish} onArchive={onArchive} />
  </section>;
}

function ProviderEditor({ provider, channels, busy, onSave, onPublish, onArchive }: {
  provider: Provider | null;
  channels: Channel[];
  busy: boolean;
  onSave: (payload: ProviderPayload, id?: string) => Promise<void>;
  onPublish: (id: string) => Promise<void>;
  onArchive: (id: string) => Promise<void>;
}): JSX.Element {
  const [form, setForm] = useState(providerForm(provider, channels));
  const [error, setError] = useState('');
  useEffect(() => { setForm(providerForm(provider, channels)); setError(''); }, [provider, channels]);
  const save = async () => {
    try {
      setError('');
      await onSave({ ...form, websiteUrl: blank(form.websiteUrl), apiKeyUrl: blank(form.apiKeyUrl), iconColor: blank(form.iconColor), configuration: parseObject(form.configurationText) }, provider?.id);
    } catch (requestError) { setError(messageOf(requestError)); }
  };
  return <section className="editor-panel">
    <EditorHeading title={provider ? '编辑供应商草稿' : '新建供应商'} state={provider?.state} />
    {error && <div className="form-error">{error}</div>}
    <div className="form-grid">
      <label>显示名称<input value={form.displayName} onChange={(event) => setForm({ ...form, displayName: event.target.value })} /></label>
      <label>供应商编码<input value={form.code} disabled={Boolean(provider)} onChange={(event) => setForm({ ...form, code: slug(event.target.value) })} /></label>
      <label>所属渠道<select value={form.channelCode} onChange={(event) => setForm({ ...form, channelCode: event.target.value })}><option value="">选择渠道</option>{channels.map((channel) => <option value={channel.code} key={channel.id}>{channel.displayName} ({channel.code})</option>)}</select></label>
      <label>分类<input value={form.category} onChange={(event) => setForm({ ...form, category: slug(event.target.value) })} /></label>
      <label>官网 URL<input value={form.websiteUrl} onChange={(event) => setForm({ ...form, websiteUrl: event.target.value })} /></label>
      <label>获取 Key URL<input value={form.apiKeyUrl} onChange={(event) => setForm({ ...form, apiKeyUrl: event.target.value })} /></label>
      <label>图标键<input value={form.iconKey} onChange={(event) => setForm({ ...form, iconKey: slug(event.target.value) })} /></label>
      <label>图标颜色<input value={form.iconColor} placeholder="#00A67E" onChange={(event) => setForm({ ...form, iconColor: event.target.value })} /></label>
    </div>
    <div className="toggle-group"><label className="toggle-row"><input type="checkbox" checked={form.enabled} onChange={(event) => setForm({ ...form, enabled: event.target.checked })} /><span>向设备下发此供应商</span></label><label className="toggle-row"><input type="checkbox" checked={form.partner} onChange={(event) => setForm({ ...form, partner: event.target.checked })} /><span>合作伙伴</span></label></div>
    <label className="json-field">供应商配置模板 JSON<textarea value={form.configurationText} onChange={(event) => setForm({ ...form, configurationText: event.target.value })} spellCheck={false} /></label>
    <div className="editor-actions">
      <button className="primary-button" onClick={() => { void save(); }} disabled={busy}><Save size={18} />保存草稿</button>
      {provider && provider.state !== 'ARCHIVED' && <button className="secondary-button" onClick={() => { void onPublish(provider.id); }} disabled={busy}><Upload size={18} />发布</button>}
      {provider && provider.state !== 'ARCHIVED' && <button className="danger-button" onClick={() => { if (window.confirm('下线该供应商后，设备将不再拉取它。')) { void onArchive(provider.id); } }} disabled={busy}><Archive size={18} />下线</button>}
    </div>
  </section>;
}

function PolicyPanel({ policy, busy, onSave, onPublish }: {
  policy: SecurityPolicy;
  busy: boolean;
  onSave: (policy: Record<string, unknown>) => Promise<void>;
  onPublish: () => Promise<void>;
}): JSX.Element {
  const [text, setText] = useState(JSON.stringify(policy.policy, null, 2));
  const [error, setError] = useState('');
  useEffect(() => { setText(JSON.stringify(policy.policy, null, 2)); setError(''); }, [policy]);
  const save = async () => { try { setError(''); await onSave(parseObject(text)); } catch (requestError) { setError(messageOf(requestError)); } };
  return <section className="policy-layout">
    <section className="editor-panel policy-editor">
      <EditorHeading title="安全策略草稿" state={undefined} />
      <div className="policy-meta"><span>草稿 v{policy.draftVersion}</span><span>已发布 v{policy.publishedVersion}</span></div>
      {error && <div className="form-error">{error}</div>}
      <label className="json-field policy-json">策略 JSON<textarea value={text} onChange={(event) => setText(event.target.value)} spellCheck={false} /></label>
      <div className="editor-actions"><button className="primary-button" onClick={() => { void save(); }} disabled={busy}><Save size={18} />保存草稿</button><button className="secondary-button" onClick={() => { void onPublish(); }} disabled={busy}><Upload size={18} />发布策略</button></div>
    </section>
    <section className="policy-rules data-panel"><div className="section-heading"><div><h2>策略规则</h2><span>发布后由设备映射到本地检测器</span></div><Settings2 size={20} /></div><PolicyRules policy={policy.policy} /></section>
  </section>;
}

function DevicePanel({ devices, busy, onIssue, onRotate, onRevoke }: {
  devices: ManagedDevice[];
  busy: boolean;
  onIssue: (name: string) => Promise<void>;
  onRotate: (id: string) => Promise<void>;
  onRevoke: (id: string) => Promise<void>;
}): JSX.Element {
  const [name, setName] = useState('');
  const issue = async (event: FormEvent<HTMLFormElement>) => { event.preventDefault(); if (name.trim()) { await onIssue(name); setName(''); } };
  return <section className="content-stack">
    <section className="data-panel device-create"><div className="section-heading"><div><h2>签发设备密钥</h2><span>密钥仅在签发或轮换时显示一次</span></div><KeyRound size={20} /></div><form onSubmit={(event) => { void issue(event); }}><input value={name} placeholder="设备名称，例如：研发部 01" onChange={(event) => setName(event.target.value)} /><button className="primary-button" type="submit" disabled={busy || !name.trim()}><Plus size={18} />签发</button></form></section>
    <section className="data-panel"><div className="section-heading"><div><h2>设备访问</h2><span>{devices.length} 台已登记设备</span></div><CloudCog size={20} /></div><div className="table-wrap"><table><thead><tr><th>设备</th><th>状态</th><th>最后在线</th><th aria-label="操作" /></tr></thead><tbody>{devices.map((device) => <tr key={device.id}><td><strong>{device.displayName}</strong><small>{device.id}</small></td><td><DeviceStatus status={device.status} /></td><td>{formatDate(device.lastSeenAt)}</td><td className="table-actions">{device.status === 'ACTIVE' && <><button className="icon-button small" title="轮换密钥" onClick={() => { void onRotate(device.id); }} disabled={busy}><RefreshCw size={16} /></button><button className="icon-button small danger" title="撤销设备" onClick={() => { if (window.confirm('撤销后该设备将无法继续拉取配置。')) { void onRevoke(device.id); } }} disabled={busy}><Archive size={16} /></button></>}</td></tr>)}</tbody></table>{devices.length === 0 && <EmptyState icon={<KeyRound size={24} />} label="尚未签发设备密钥" />}</div></section>
  </section>;
}

function DeviceKeyDialog({ issued, onClose }: { issued: IssuedDevice; onClose: () => void }): JSX.Element {
  const [copied, setCopied] = useState(false);
  const copy = async () => { await navigator.clipboard.writeText(issued.deviceKey); setCopied(true); };
  return <div className="modal-backdrop" role="presentation"><section className="key-dialog" role="dialog" aria-modal="true" aria-labelledby="key-title"><button className="icon-button close" title="关闭" onClick={onClose}><X size={19} /></button><span className="dialog-icon"><KeyRound size={24} /></span><h2 id="key-title">设备密钥已签发</h2><p>{issued.device.displayName}</p><code>{issued.deviceKey}</code><button className="primary-button full-width" onClick={() => { void copy(); }}><Clipboard size={18} />{copied ? '已复制' : '复制密钥'}</button></section></div>;
}

function EventTable({ events }: { events: Overview['recentEvents'] }): JSX.Element {
  return <div className="table-wrap"><table><thead><tr><th>时间</th><th>事件</th><th>渠道</th><th>规则</th><th>级别</th></tr></thead><tbody>{events.map((event) => <tr key={event.id}><td>{formatDate(event.receivedAt)}</td><td>{event.eventType}</td><td>{event.channelCode ?? '—'}</td><td>{event.ruleId ?? '—'}</td><td><SeverityBadge severity={event.severity} /></td></tr>)}</tbody></table>{events.length === 0 && <EmptyState icon={<Activity size={24} />} label="暂无事件" />}</div>;
}

function PolicyRules({ policy }: { policy: Record<string, unknown> }): JSX.Element {
  const rules = Array.isArray(policy.rules) ? policy.rules : [];
  return <div className="rule-list">{rules.map((rule, index) => {
    const item = typeof rule === 'object' && rule !== null ? rule as Record<string, unknown> : {};
    return <div className="rule-row" key={`${String(item.ruleId)}-${index}`}><span><ShieldCheck size={17} /></span><strong>{String(item.ruleId ?? '未命名规则')}</strong><SeverityBadge severity={String(item.action ?? 'WARN') as 'INFO' | 'WARN' | 'BLOCK' | 'ERROR'} /></div>;
  })}</div>;
}

function EditorHeading({ title, state }: { title: string; state?: Channel['state'] }): JSX.Element {
  return <div className="editor-heading"><div><h2>{title}</h2>{state && <StateBadge state={state} />}</div><Pencil size={20} /></div>;
}

function StateBadge({ state }: { state: Channel['state'] }): JSX.Element { return <span className={`state-badge ${state.toLowerCase()}`}>{state === 'PUBLISHED' ? '已发布' : state === 'ARCHIVED' ? '已下线' : '草稿'}</span>; }
function DeviceStatus({ status }: { status: ManagedDevice['status'] }): JSX.Element { return <span className={`state-badge ${status === 'ACTIVE' ? 'published' : 'archived'}`}>{status === 'ACTIVE' ? '有效' : '已撤销'}</span>; }
function SeverityBadge({ severity }: { severity: 'INFO' | 'WARN' | 'BLOCK' | 'ERROR' }): JSX.Element { return <span className={`severity ${severity.toLowerCase()}`}>{severity}</span>; }
function EmptyState({ icon, label }: { icon: JSX.Element; label: string }): JSX.Element { return <div className="empty-state">{icon}<span>{label}</span></div>; }

function channelForm(channel: Channel | null): ChannelPayload & { configurationText: string } {
  return channel ? { ...channel, documentationUrl: channel.documentationUrl ?? '', configurationText: JSON.stringify(channel.configuration, null, 2) } : {
    code: '', displayName: '', clientType: 'claude', protocol: 'anthropic', iconKey: 'plug', documentationUrl: '', localConfigPathHint: '~/.claude/settings.json', enabled: true,
    configuration: DEFAULT_CHANNEL_CONFIGURATION, configurationText: JSON.stringify(DEFAULT_CHANNEL_CONFIGURATION, null, 2)
  };
}

function providerForm(provider: Provider | null, channels: Channel[]): ProviderPayload & { configurationText: string } {
  return provider ? { ...provider, websiteUrl: provider.websiteUrl ?? '', apiKeyUrl: provider.apiKeyUrl ?? '', iconColor: provider.iconColor ?? '', configurationText: JSON.stringify(provider.configuration, null, 2) } : {
    code: '', displayName: '', channelCode: channels[0]?.code ?? '', category: 'third_party', websiteUrl: '', apiKeyUrl: '', iconKey: 'server', iconColor: '', partner: false, enabled: true,
    configuration: DEFAULT_PROVIDER_CONFIGURATION, configurationText: JSON.stringify(DEFAULT_PROVIDER_CONFIGURATION, null, 2)
  };
}

function parseObject(text: string): Record<string, unknown> { const value: unknown = JSON.parse(text); if (typeof value !== 'object' || value === null || Array.isArray(value)) { throw new Error('配置必须是 JSON 对象'); } return value as Record<string, unknown>; }
function slug(value: string): string { return value.toLowerCase().replace(/[^a-z0-9_-]/g, ''); }
function blank(value?: string): string | undefined { return value?.trim() || undefined; }
function formatDate(value?: string): string { return value ? new Intl.DateTimeFormat('zh-CN', { dateStyle: 'short', timeStyle: 'medium' }).format(new Date(value)) : '—'; }
function messageOf(error: unknown): string { return error instanceof Error ? error.message : '请求失败'; }
