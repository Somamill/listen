def describe(torrent):
    progress=float(torrent.get('progress') or 0)
    state=str(torrent.get('state','')).casefold()
    seeds=torrent.get('seeds');peers=torrent.get('peers');availability=torrent.get('availability')
    if any(x in state for x in ('error','missing')):return {'kind':'error','label':'Needs attention','detail':'The client reports an error or missing files.'}
    if progress>=1:return {'kind':'complete','label':'Ready to listen','detail':'The client reports all files downloaded. This is not a malware or file-integrity assessment.'}
    if 'check' in state or 'meta' in state:return {'kind':'checking','label':'Checking / metadata','detail':'The client is checking files or retrieving torrent metadata.'}
    if seeds and seeds>0 and (availability is None or availability>=1):return {'kind':'healthy','label':'Sources available','detail':'Connected seeds or complete availability were reported by your client.'}
    if (peers and peers>0) or (torrent.get('download_speed') or 0)>0:return {'kind':'limited','label':'Active peers','detail':'Peers or a transfer were reported. Speed and completion are not guaranteed.'}
    return {'kind':'unknown','label':'Waiting for sources','detail':'No active sources were reported. This can change as peers become available.'}
